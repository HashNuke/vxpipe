defmodule Vxpipe.Console.IntegrationsDirectory.Cache do
  @moduledoc "Bounded public-page cache with coalesced, supervised directory requests."
  use GenServer

  alias Vxpipe.Console.IntegrationsDirectory.{Page, Request, Transport}

  def start_link(options) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, if(name, do: [name: name], else: []))
  end

  def fetch(resource, params, server \\ __MODULE__) do
    with {:ok, request} <- Request.build(resource, params) do
      GenServer.call(server, {:fetch, request}, 15_000)
    end
  end

  @impl true
  def init(options) do
    {:ok,
     %{
       entries: %{},
       cooldown: nil,
       pending: %{},
       tasks: %{},
       sequence: 0,
       bytes: 0,
       ttl: Keyword.get(options, :ttl, 3_600_000),
       max_entries: Keyword.get(options, :max_entries, 128),
       max_bytes: Keyword.get(options, :max_bytes, 16 * 1_048_576),
       max_tasks: Keyword.get(options, :max_tasks, 8),
       max_waiters: Keyword.get(options, :max_waiters, 64),
       timeout: Keyword.get(options, :timeout, 12_000),
       clock: Keyword.get(options, :clock, fn -> System.monotonic_time(:millisecond) end),
       loader: Keyword.get(options, :loader, &load_page/2),
       supervisor:
         Keyword.get(options, :task_supervisor, Vxpipe.Console.IntegrationsDirectory.Tasks)
     }}
  end

  @impl true
  def handle_call({:fetch, request}, from, state) do
    case Map.get(state.entries, request) do
      %{expires: expires, response: response} ->
        if expires > state.clock.() do
          {:reply, {:ok, response}, touch(state, request)}
        else
          enqueue(state, request, from)
        end

      _missing ->
        enqueue(state, request, from)
    end
  end

  defp enqueue(state, request, from) do
    origin = origin(request)

    case state.cooldown do
      {^origin, until} ->
        if until > state.clock.(),
          do: {:reply, {:error, :rate_limited}, state},
          else: enqueue_ready(%{state | cooldown: nil}, request, from)

      _ ->
        enqueue_ready(state, request, from)
    end
  end

  defp enqueue_ready(state, request, from) do
    case Map.fetch(state.pending, request) do
      {:ok, ref} ->
        job = Map.fetch!(state.tasks, ref)

        if length(job.waiters) < state.max_waiters do
          {:noreply, put_in(state, [:tasks, ref, :waiters], [from | job.waiters])}
        else
          {:reply, {:error, :busy}, state}
        end

      :error when map_size(state.tasks) >= state.max_tasks ->
        {:reply, {:error, :busy}, state}

      :error ->
        start_fetch(state, request, from)
    end
  end

  defp start_fetch(state, request, from) do
    cached = Map.get(state.entries, request)
    loader = state.loader

    task =
      Task.Supervisor.async_nolink(state.supervisor, fn -> revalidate(loader, request, cached) end)

    timer = Process.send_after(self(), {:fetch_timeout, task.ref}, state.timeout)
    job = %{request: request, waiters: [from], timer: timer, pid: task.pid}

    {:noreply,
     %{
       state
       | tasks: Map.put(state.tasks, task.ref, job),
         pending: Map.put(state.pending, request, task.ref)
     }}
  rescue
    RuntimeError -> {:reply, {:error, :busy}, state}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    finish(state, ref, result)
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state),
    do: finish(state, ref, {:error, :unavailable})

  def handle_info({:fetch_timeout, ref}, state) do
    case Map.fetch(state.tasks, ref) do
      {:ok, job} ->
        Process.exit(job.pid, :kill)
        finish(state, ref, {:error, :timeout})

      :error ->
        {:noreply, state}
    end
  end

  defp finish(state, ref, result) do
    case Map.pop(state.tasks, ref) do
      {nil, _tasks} ->
        {:noreply, state}

      {job, tasks} ->
        Process.cancel_timer(job.timer)
        {result, state} = rate_limit(result, state, job.request)
        Enum.each(job.waiters, &GenServer.reply(&1, result))
        state = %{state | tasks: tasks, pending: Map.delete(state.pending, job.request)}

        state =
          case result do
            {:ok, response} -> store(state, job.request, response)
            {:error, _reason} -> delete_entry(state, job.request)
          end

        {:noreply, state}
    end
  end

  defp rate_limit({:error, {:rate_limited, delay}}, state, request)
       when is_integer(delay) and delay >= 0 do
    origin = origin(request)
    deadline = state.clock.() + min(delay, 86_400_000)

    until =
      case state.cooldown do
        {^origin, existing} -> max(existing, deadline)
        _ -> deadline
      end

    {{:error, :rate_limited}, %{state | cooldown: {origin, until}}}
  end

  defp rate_limit(result, state, _request), do: {result, state}

  defp origin(request), do: request.url |> URI.parse() |> Map.put(:path, nil) |> URI.to_string()

  defp revalidate(loader, request, nil) do
    case loader.(request, nil) do
      :not_modified ->
        case loader.(request, nil) do
          :not_modified -> {:error, :invalid_response}
          result -> result
        end

      result ->
        result
    end
  end

  defp revalidate(loader, request, cached) do
    case loader.(request, cached.response.etag) do
      :not_modified -> {:ok, cached.response}
      result -> result
    end
  end

  defp load_page(request, etag) do
    with {:ok, response} <- Transport.fetch(request, etag: etag),
         {:ok, page} <- Page.validate(response.body, request) do
      {:ok, %{response | body: page}}
    end
  end

  defp store(state, request, response) do
    state = delete_entry(state, request)
    size = :erlang.external_size({request, response})

    if size <= state.max_bytes and state.max_entries > 0 do
      sequence = state.sequence + 1

      entry = %{
        response: response,
        size: size,
        expires: state.clock.() + state.ttl,
        touched: sequence
      }

      evict(%{
        state
        | entries: Map.put(state.entries, request, entry),
          bytes: state.bytes + size,
          sequence: sequence
      })
    else
      state
    end
  end

  defp touch(state, request) do
    state
    |> put_in([:entries, request, :touched], state.sequence + 1)
    |> Map.put(:sequence, state.sequence + 1)
  end

  defp evict(state)
       when map_size(state.entries) <= state.max_entries and state.bytes <= state.max_bytes,
       do: state

  defp evict(state) do
    {request, _entry} = Enum.min_by(state.entries, fn {_key, entry} -> entry.touched end)
    state |> delete_entry(request) |> evict()
  end

  defp delete_entry(state, request) do
    case Map.pop(state.entries, request) do
      {nil, _entries} -> state
      {entry, entries} -> %{state | entries: entries, bytes: state.bytes - entry.size}
    end
  end
end
