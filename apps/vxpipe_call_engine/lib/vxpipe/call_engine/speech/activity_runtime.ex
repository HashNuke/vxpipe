defmodule Vxpipe.CallEngine.Speech.ActivityRuntime do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Speech.Silero
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, InferenceAdmission}

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))

  def submit(%Silero{} = stream, audio, server) do
    if Silero.valid_audio?(audio),
      do: GenServer.call(server, {:submit, stream, audio}, 5_000),
      else: {:error, :invalid_audio}
  end

  def diagnostic_admission(server), do: GenServer.call(server, :diagnostic_admission)

  def cancel(reference, server),
    do: GenServer.call(server, {:cancel, reference}, 5_000)

  @impl true
  def init(options) do
    {:ok,
     %{
       tasks: Keyword.fetch!(options, :task_supervisor),
       load: Keyword.get(options, :load, &Silero.ModelCache.fetch/0),
       classify: Keyword.get(options, :classify, &classify/3),
       max_jobs: Keyword.get(options, :max_jobs, 1),
       load_timeout: Keyword.get(options, :load_timeout_ms, 15_000),
       inference_timeout: Keyword.get(options, :inference_timeout_ms, 2_000),
       admission: InferenceAdmission.new(self(), Keyword.get(options, :diagnostic_capacity)),
       model: nil,
       jobs: %{}
     }}
  end

  @impl true
  def handle_call(:diagnostic_admission, _from, state), do: {:reply, state.admission, state}

  def handle_call({:submit, stream, audio}, {owner, _tag}, state) do
    if busy?(state, owner) do
      {:reply, {:error, :busy}, state}
    else
      {reference, state} = start_job(state, owner, stream, audio, nil)
      {:reply, {:ok, reference}, state}
    end
  end

  def handle_call({:cancel, reference}, {owner, _tag}, state) do
    case Map.fetch(state.jobs, reference) do
      {:ok, %{owner: ^owner, status: :active} = job} ->
        {:reply, :ok, retire(state, reference, job, :cancelled)}

      _other ->
        {:reply, {:error, :unknown_job}, state}
    end
  end

  @impl true
  def handle_info(
        {:diagnostic_inference, token, owner, reference, grant, stream, audio},
        %{admission: %InferenceAdmission{token: token}} = state
      ) do
    diagnostic = {state.admission, grant, reference}

    cond do
      not CaptureHandoff.current?(grant) ->
        InferenceAdmission.release(state.admission)
        {:noreply, state}

      busy?(state, owner) ->
        InferenceAdmission.release(state.admission)
        send(owner, {:vxpipe_speech_activity, reference, {:error, :busy}})
        {:noreply, state}

      true ->
        {_reference, state} = start_job(state, owner, stream, audio, diagnostic)
        {:noreply, state}
    end
  end

  def handle_info({:check_grant, reference}, state) do
    case Map.fetch(state.jobs, reference) do
      {:ok, %{status: :active, diagnostic: {_, grant, _}} = job} ->
        if CaptureHandoff.current?(grant) do
          job = %{job | grant_timer: Process.send_after(self(), {:check_grant, reference}, 250)}
          {:noreply, %{state | jobs: Map.put(state.jobs, reference, job)}}
        else
          {:noreply, retire(state, reference, job, :abandoned)}
        end

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({reference, result}, state) when is_reference(reference) do
    case Map.fetch(state.jobs, reference) do
      :error ->
        {:noreply, state}

      {:ok, job} ->
        if job.timer, do: Process.cancel_timer(job.timer)
        job = %{job | result: result, timer: nil}
        {:noreply, %{state | jobs: Map.put(state.jobs, reference, job)}}
    end
  end

  def handle_info({:deadline, reference}, state) do
    case Map.fetch(state.jobs, reference) do
      {:ok, %{status: :active, result: nil} = job} ->
        deliver(job, reference, {:error, :classification_timeout})
        {:noreply, retire(state, reference, job, :timed_out)}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, reference, :process, _pid, _reason}, state) do
    case Map.pop(state.jobs, reference) do
      {nil, _jobs} ->
        {:noreply, owner_down(state, reference)}

      {job, jobs} ->
        cleanup(job)
        if job.diagnostic, do: InferenceAdmission.release(elem(job.diagnostic, 0))
        {model, result} = outcome(job.result, state.model)
        deliver(job, reference, result)
        {:noreply, %{state | jobs: jobs, model: model}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, %{
      jobs: map_size(status.state.jobs),
      model_loaded?: not is_nil(status.state.model)
    })
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp busy?(state, owner),
    do:
      map_size(state.jobs) >= state.max_jobs or
        (is_nil(state.model) and map_size(state.jobs) > 0) or
        Enum.any?(state.jobs, fn {_ref, job} -> job.owner == owner end)

  defp start_job(state, owner, stream, audio, diagnostic) do
    task =
      Task.Supervisor.async_nolink(state.tasks, fn -> run(state, stream, audio, diagnostic) end)

    timeout = if is_nil(state.model), do: state.load_timeout, else: state.inference_timeout

    job = %{
      task: task,
      owner: owner,
      owner_ref: Process.monitor(owner),
      timer: Process.send_after(self(), {:deadline, task.ref}, timeout),
      diagnostic: diagnostic,
      grant_timer: if(diagnostic, do: Process.send_after(self(), {:check_grant, task.ref}, 250)),
      result: nil,
      status: :active
    }

    {task.ref, %{state | jobs: Map.put(state.jobs, task.ref, job)}}
  end

  defp run(state, stream, audio, diagnostic) do
    if current?(diagnostic),
      do: classify_current(state, stream, audio, diagnostic),
      else: {:error, :revoked}
  end

  defp classify_current(state, stream, audio, diagnostic) do
    loaded = if is_nil(state.model), do: state.load.(), else: {:ok, state.model}

    case loaded do
      {:ok, model} ->
        if current?(diagnostic),
          do: {:ok, model, state.classify.(model, stream, audio)},
          else: {:error, :revoked}

      _failure ->
        {:error, :model_unavailable}
    end
  rescue
    _error -> {:error, :classification_failed}
  catch
    _kind, _reason -> {:error, :classification_failed}
  end

  defp classify(model, stream, audio), do: Silero.push(stream, model, audio)

  defp outcome({:ok, model, {:ok, %Silero{} = stream, probabilities}}, _old),
    do: {model, {:ok, stream, probabilities}}

  defp outcome({:ok, model, _failure}, _old), do: {model, {:error, :classification_failed}}
  defp outcome({:error, :model_unavailable}, old), do: {old, {:error, :model_unavailable}}
  defp outcome(_failure, old), do: {old, {:error, :classification_failed}}

  defp retire(state, reference, job, status) do
    cleanup(job)
    Process.exit(job.task.pid, :kill)
    # A native call may outlive cancellation. Keep its slot until actual task settlement.
    job = %{job | status: status, timer: nil, owner_ref: nil}
    %{state | jobs: Map.put(state.jobs, reference, job)}
  end

  defp owner_down(state, reference) do
    Enum.reduce(state.jobs, state, fn
      {task_ref, %{owner_ref: ^reference} = job}, current ->
        retire(current, task_ref, job, :abandoned)

      _other, current ->
        current
    end)
  end

  defp cleanup(job) do
    if job.timer, do: Process.cancel_timer(job.timer)
    if job.grant_timer, do: Process.cancel_timer(job.grant_timer)
    if job.owner_ref, do: Process.demonitor(job.owner_ref, [:flush])
    :ok
  end

  defp current?(nil), do: true
  defp current?({_admission, grant, _reference}), do: CaptureHandoff.current?(grant)

  defp deliver(%{status: :active, owner: owner, diagnostic: diagnostic}, reference, result) do
    if current?(diagnostic) do
      reference = if diagnostic, do: elem(diagnostic, 2), else: reference
      send(owner, {:vxpipe_speech_activity, reference, result})
    end
  end

  defp deliver(%{status: :cancelled, owner: owner}, reference, _result),
    do: send(owner, {:vxpipe_speech_activity, reference, {:error, :cancelled}})

  defp deliver(_job, _reference, _result), do: :ok
end
