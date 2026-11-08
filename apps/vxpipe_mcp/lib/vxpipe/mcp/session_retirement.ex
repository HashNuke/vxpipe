defmodule Vxpipe.MCP.SessionRetirement do
  @moduledoc false

  alias Vxpipe.MCP.{Connection, ConnectionNames, SessionLifecycle, Telemetry}

  @registry Vxpipe.MCP.ConnectionRegistry

  def close_all(connections, opts) do
    started_at = Telemetry.started_at()
    descriptions = Enum.flat_map(connections, &describe/1)
    requested = Enum.map(connections, &{Connection.owner(&1), Connection.client(&1)})
    report_close(descriptions, requested, opts, started_at)
  end

  def close_owners(key, owners, opts \\ []) do
    started_at = Telemetry.started_at()

    descriptions =
      Enum.flat_map(owners, fn {parent, integration} ->
        describe_owner(key, parent, integration, :any)
      end)

    requested = Enum.map(owners, fn {_parent, integration} -> {integration, nil} end)
    report_close(descriptions, requested, opts, started_at)
  end

  def close_owned(keys, parent, opts) do
    started_at = Telemetry.started_at()

    descriptions =
      keys
      |> Enum.uniq()
      |> Enum.flat_map(fn key ->
        key
        |> ConnectionNames.owned_sessions(parent)
        |> Enum.flat_map(&describe_owner(key, parent, &1, :any))
      end)

    requested = Enum.map(descriptions, &{&1.integration, &1.client})
    report_close(descriptions, requested, opts, started_at)
  end

  defp report_close(descriptions, requested, opts, started_at) do
    result = retire(descriptions, opts)
    by_integration = Map.new(descriptions, &{&1.integration, &1.client})

    Enum.each(requested, fn {integration, previous_client} ->
      {outcome, client} =
        case Map.fetch(by_integration, integration) do
          {:ok, client} -> {if(result == :ok, do: :closed, else: :failed), client}
          :error -> {:absent, previous_client}
        end

      Telemetry.connection_stop(started_at, :close, outcome, ConnectionNames.count(), client)
    end)

    result
  end

  defp retire(descriptions, opts) do
    deadline = Keyword.get(opts, :deadline, now() + 1_000)
    caller = self()

    sessions =
      descriptions
      |> Enum.uniq_by(& &1.integration)
      |> Enum.map(&monitor/1)
      |> Enum.map(&fence(&1, caller, deadline))

    sessions
    |> Task.async_stream(&cleanup(&1, deadline),
      max_concurrency: 8,
      timeout: max(deadline - now(), 1),
      on_timeout: :kill_task
    )
    |> Stream.run()

    Enum.each(sessions, &force/1)
    termination_deadline = now() + 5_000
    results = Enum.map(sessions, &await_termination(&1, termination_deadline))
    if Enum.all?(results, &(&1 == :ok)), do: :ok, else: {:error, :cleanup_incomplete}
  end

  defp describe(connection) do
    key = Connection.key(connection)
    integration = Connection.owner(connection)
    parent = Connection.session_owner(connection)
    client = Connection.client(connection)

    describe_owner(key, parent, integration, client)
  end

  defp describe_owner(key, parent, integration, expected_client) do
    Enum.find_value([parent, nil], [], fn scope ->
      name = if scope, do: {:owner, scope, key}, else: {:owner, key}

      case Registry.lookup(@registry, name) do
        [{^integration, %{parent: ^parent, runtime: runtime}}] ->
          current = ConnectionNames.client(key, scope, integration)

          if Process.alive?(integration) and
               (current == :error or expected_client == :any or current == {:ok, expected_client}) do
            actual_client =
              case current do
                {:ok, client} -> client
                :error -> nil
              end

            [%{integration: integration, client: actual_client, runtime: runtime}]
          end

        _ ->
          nil
      end
    end)
    |> remaining_transport(key, parent, integration)
  end

  defp remaining_transport([], key, parent, integration) do
    case Registry.lookup(@registry, {:transport_workers, integration}) do
      [{transport, %{parent: ^parent, key: ^key}}] ->
        if Process.alive?(integration) or not Process.alive?(transport),
          do: [],
          else: [%{integration: integration, client: nil, runtime: nil}]

      _ ->
        []
    end
  end

  defp remaining_transport(sessions, _key, _parent, _integration), do: sessions

  defp monitor(session) do
    transport =
      GenServer.whereis({:via, Registry, {@registry, {:transport_workers, session.integration}}})

    guard = GenServer.whereis(SessionLifecycle.name(session.integration))

    monitors =
      [session.integration, session.client, transport, guard]
      |> Enum.filter(&is_pid/1)
      |> Enum.uniq()
      |> Map.new(&{&1, Process.monitor(&1)})

    Map.put(session, :monitors, monitors)
  end

  defp fence(session, caller, deadline) do
    permission =
      if now() < deadline and is_pid(session.client) do
        SessionLifecycle.begin_close(session.integration, session.client, caller, deadline)
      else
        force(session)
        :unavailable
      end

    Map.put(session, :permission, permission)
  catch
    :exit, _reason ->
      force(session)
      Map.put(session, :permission, :unavailable)
  end

  defp cleanup(%{permission: {:ok, permission}} = session, deadline) do
    remaining = max(deadline - now(), 0)

    if remaining > 0 and function_exported?(session.runtime, :close, 3) do
      session.runtime.close(session.client, permission, remaining)
    end

    Supervisor.stop(session.integration, :shutdown, max(deadline - now(), 1))
  rescue
    _exception -> :ok
  catch
    :exit, _reason -> :ok
  after
    force(session)
  end

  defp cleanup(session, _deadline), do: force(session)

  # Killing the integration makes its transport supervisor perform orderly child
  # shutdown. Killing that supervisor itself would lose the descendant barrier.
  defp force(session) do
    if is_pid(session.client), do: Process.exit(session.client, :kill)
    Process.exit(session.integration, :kill)
    :ok
  end

  defp await_termination(session, deadline) do
    Enum.reduce(session.monitors, :ok, fn {pid, ref}, result ->
      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> result
      after
        max(deadline - now(), 0) ->
          Process.demonitor(ref, [:flush])
          {:error, :cleanup_incomplete}
      end
    end)
  end

  defp now, do: System.monotonic_time(:millisecond)
end
