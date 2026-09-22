defmodule Vxpipe.CallEngine.MediaPolicy.Authority do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.MediaPolicy.{
    Barrier,
    Candidate,
    Effective,
    Enforcer,
    PrivateRegistration,
    Snapshot
  }

  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.ResolvedCallPlan.{MediaPolicy, Participant}

  @call_timeout 5_000
  @default_enforcement_timeout_ms 1_000

  def start_link(options) do
    name = if Keyword.get(options, :register, true), do: via(options), else: nil
    GenServer.start_link(__MODULE__, options, name: name)
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :incarnation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      significant: true
    }
  end

  @spec whereis(String.t()) :: pid() | nil
  def whereis(incarnation_id) when is_binary(incarnation_id) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, registry_key(incarnation_id)) do
      [{server, _value}] -> server
      [] -> nil
    end
  end

  @spec snapshot(GenServer.server(), timeout()) :: Snapshot.t()
  def snapshot(server, timeout \\ @call_timeout), do: GenServer.call(server, :snapshot, timeout)

  @spec preview_presence(GenServer.server(), MapSet.t(String.t()), timeout()) ::
          {:ok, Candidate.t()} | {:error, atom()}
  def preview_presence(server, present, timeout \\ @call_timeout),
    do: GenServer.call(server, {:preview_presence, present}, timeout)

  @spec validate_candidate(GenServer.server(), Candidate.t(), timeout()) ::
          :ok | {:error, :invalid_candidate | :stale_candidate}
  def validate_candidate(server, candidate, timeout \\ @call_timeout),
    do: GenServer.call(server, {:validate_candidate, candidate}, timeout)

  @doc "Installs the exact prospective membership within the original absolute phase deadline."
  @spec commit_candidate(GenServer.server(), Candidate.t(), integer(), [pid() | {pid(), pid()}]) ::
          {:ok, Snapshot.t()}
          | {:error,
             :invalid_deadline
             | :deadline_elapsed
             | :invalid_candidate
             | :invalid_enforcers
             | :invalid_private_enforcers
             | :stale_candidate
             | :unchanged_candidate
             | :enforcement_failed}
  def commit_candidate(server, candidate, deadline_ms, new_enforcers \\ []),
    do:
      GenServer.call(
        server,
        {:commit_candidate, candidate, deadline_ms, new_enforcers},
        @call_timeout
      )

  @doc "Promotes exact private attempt ownership before entering the candidate barrier."
  def commit_candidate(server, candidate, deadline_ms, enforcers, private_scope),
    do:
      GenServer.call(
        server,
        {:commit_private_candidate, candidate, deadline_ms, enforcers, private_scope},
        @call_timeout
      )

  @doc "Subscribes an authorized private allocation without making cancellation room-critical."
  def register_private_enforcers(server, enforcers, connection, scope, timeout \\ @call_timeout),
    do:
      GenServer.call(server, {:register_private_enforcers, enforcers, connection, scope}, timeout)

  @spec register_enforcer(GenServer.server(), pid(), timeout()) ::
          {:ok, Snapshot.t()} | {:error, :already_registered | :enforcement_failed}
  def register_enforcer(server, enforcer, timeout \\ @call_timeout) when is_pid(enforcer) do
    GenServer.call(server, {:register_enforcer, enforcer, nil}, timeout)
  end

  @doc "Registers an enforcer required only while its exact transport connection exists."
  @spec register_connection_enforcer(GenServer.server(), pid(), pid(), timeout()) ::
          {:ok, Snapshot.t()}
          | {:error, :already_registered | :connection_unavailable | :enforcement_failed}
  def register_connection_enforcer(server, enforcer, connection, timeout \\ @call_timeout)
      when is_pid(enforcer) and is_pid(connection) do
    GenServer.call(server, {:register_enforcer, enforcer, connection}, timeout)
  end

  @doc "Registers policy enforcers that must stop together when one member fails."
  @spec register_connection_enforcers(GenServer.server(), [pid()], pid(), timeout()) ::
          {:ok, Snapshot.t()}
          | {:error,
             :already_registered
             | :connection_unavailable
             | :enforcement_failed
             | :invalid_enforcers}
  def register_connection_enforcers(server, enforcers, connection, timeout \\ @call_timeout)
      when is_list(enforcers) and is_pid(connection) do
    GenServer.call(server, {:register_enforcer_group, enforcers, connection}, timeout)
  end

  @doc "Retires selected enforcers before teardown; selecting a group member retires its group."
  @spec retire_connection_enforcers(GenServer.server(), pid(), [pid()], timeout()) :: :ok
  def retire_connection_enforcers(server, connection, enforcers, timeout \\ @call_timeout)
      when is_pid(connection) and is_list(enforcers) do
    GenServer.call(server, {:retire_connection_enforcers, connection, enforcers}, timeout)
  end

  @spec admit(GenServer.server(), String.t(), timeout()) ::
          {:ok, Snapshot.t()}
          | {:error,
             :already_present
             | :enforcement_failed
             | :invalid_policy
             | :invalid_private_enforcers
             | :unknown_participant}
  def admit(server, participant_id, timeout \\ @call_timeout) when is_binary(participant_id) do
    GenServer.call(server, {:admit, participant_id}, timeout)
  end

  @spec leave(GenServer.server(), String.t(), timeout()) ::
          {:ok, Snapshot.t()} | {:error, :enforcement_failed | :invalid_policy | :not_present}
  def leave(server, participant_id, timeout \\ @call_timeout) when is_binary(participant_id) do
    GenServer.call(server, {:leave, participant_id}, timeout)
  end

  @impl true
  def init(options) do
    plan = Keyword.fetch!(options, :plan)
    host_ceiling = Keyword.get(options, :media_policy_ceiling, MediaPolicy.inherit())

    with {:ok, enforcement_timeout_ms} <- enforcement_timeout(options),
         %ResolvedCallPlan{} <- plan,
         {:ok, participant_policies} <- participant_policies(plan.participants),
         {:ok, effective} <- Effective.compose(host_ceiling, plan.media_policy, %{}) do
      {:ok,
       %{
         host_ceiling: host_ceiling,
         normal_policy: plan.media_policy,
         participant_policies: participant_policies,
         contributions: %{},
         enforcement_timeout_ms: enforcement_timeout_ms,
         enforcers: %{},
         connection_monitors: %{},
         snapshot: %Snapshot{
           revision: 0,
           present_participant_ids: MapSet.new(),
           effective: effective
         }
       }}
    else
      {:error, reason} -> {:stop, reason}
      _invalid -> {:stop, :invalid_policy}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  def handle_call({:preview_presence, present}, _from, state) do
    {:reply, Candidate.new(self(), present, state), state}
  end

  def handle_call({:validate_candidate, candidate}, _from, state) do
    {:reply, Candidate.validate(candidate, self(), state), state}
  end

  def handle_call({:commit_candidate, _candidate, deadline, _enforcers}, _from, state)
      when not is_integer(deadline),
      do: {:reply, {:error, :invalid_deadline}, state}

  def handle_call({:commit_candidate, candidate, deadline, enforcers}, _from, state) do
    commit_selected(candidate, deadline, enforcers, nil, state)
  end

  def handle_call(
        {:commit_private_candidate, candidate, deadline, enforcers, scope},
        _from,
        state
      ) do
    commit_selected(candidate, deadline, enforcers, scope, state)
  end

  def handle_call({:register_private_enforcers, enforcers, connection, scope}, _from, state) do
    if PrivateRegistration.valid_scope?(scope, state.snapshot, state.participant_policies),
      do: register_group(enforcers, connection, scope, state),
      else: {:reply, {:error, :invalid_private_scope}, state}
  end

  def handle_call({:register_enforcer, enforcer, connection}, _from, state) do
    cond do
      Map.has_key?(state.enforcers, enforcer) ->
        {:reply, {:error, :already_registered}, state}

      connection != nil and not Process.alive?(connection) ->
        {:reply, {:error, :connection_unavailable}, state}

      true ->
        case Enforcer.apply(enforcer, state.snapshot, state.enforcement_timeout_ms) do
          :ok ->
            {:reply, {:ok, state.snapshot}, monitor_enforcer(enforcer, connection, state)}

          {:error, _reason} ->
            {:stop, :media_policy_enforcement_failed, {:error, :enforcement_failed}, state}
        end
    end
  end

  def handle_call({:register_enforcer_group, enforcers, connection}, _from, state) do
    register_group(enforcers, connection, nil, state)
  end

  def handle_call({:retire_connection_enforcers, connection, enforcers}, _from, state) do
    {:reply, :ok, retire_enforcers(connection, enforcers, state)}
  end

  def handle_call({:admit, participant_id}, _from, state) do
    cond do
      Map.has_key?(state.contributions, participant_id) ->
        {:reply, {:error, :already_present}, state}

      not PrivateRegistration.admission_available?(state.enforcers, participant_id) ->
        {:reply, {:error, :invalid_private_enforcers}, state}

      true ->
        case Map.fetch(state.participant_policies, participant_id) do
          {:ok, policy} -> commit(Map.put(state.contributions, participant_id, policy), state)
          :error -> {:reply, {:error, :unknown_participant}, state}
        end
    end
  end

  def handle_call({:leave, participant_id}, _from, state) do
    if Map.has_key?(state.contributions, participant_id) do
      commit(Map.delete(state.contributions, participant_id), state)
    else
      {:reply, {:error, :not_present}, state}
    end
  end

  defp commit_selected(_candidate, deadline, _enforcers, _scope, state)
       when not is_integer(deadline),
       do: {:reply, {:error, :invalid_deadline}, state}

  defp commit_selected(candidate, deadline, enforcers, scope, state) do
    with :ok <- Candidate.validate(candidate, self(), state),
         :ok <- validate_enforcers(enforcers),
         :ok <-
           PrivateRegistration.validate_selection(
             state.enforcers,
             enforcers,
             scope,
             deadline,
             candidate
           ) do
      install_candidate(candidate.snapshot, deadline, enforcers, state)
    else
      {:error, :invalid_enforcers} when is_map(scope) ->
        # A scoped receipt whose connection died has not entered the barrier.
        # Keep this private preparation rejection distinct from uncertain apply.
        {:reply, {:error, :invalid_private_enforcers}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  defp register_group(enforcers, connection, scope, state)
       when is_list(enforcers) and is_pid(connection) do
    group = MapSet.new(enforcers)

    cond do
      not valid_enforcer_group?(group) ->
        {:reply, {:error, :invalid_enforcers}, state}

      MapSet.size(group) != length(enforcers) ->
        {:reply, {:error, :already_registered}, state}

      Enum.any?(group, &Map.has_key?(state.enforcers, &1)) ->
        {:reply, {:error, :already_registered}, state}

      not Process.alive?(connection) ->
        {:reply, {:error, :connection_unavailable}, state}

      true ->
        lease = PrivateRegistration.start(scope)
        state = Enum.reduce(group, state, &monitor_enforcer(&1, connection, &2, group, lease))
        registered = Map.take(state.enforcers, MapSet.to_list(group))
        deadline = System.monotonic_time(:millisecond) + state.enforcement_timeout_ms
        deadline = if scope, do: min(deadline, scope.deadline_ms), else: deadline

        result =
          with :ok <- Barrier.apply(registered, state.snapshot, remaining(deadline)),
               true <-
                 lease == nil or
                   (PrivateRegistration.active?(lease) and
                      System.monotonic_time(:millisecond) < deadline),
               do: :ok

        case result do
          :ok ->
            {:reply, {:ok, state.snapshot}, state}

          _failed_or_expired ->
            # Expiry cannot succeed or extend the preparation lease. Teardown
            # alone gets a bounded cleanup budget after that failed registration.
            cleanup_deadline =
              if scope,
                do: System.monotonic_time(:millisecond) + state.enforcement_timeout_ms,
                else: deadline

            case retire_enforcer_group(group, nil, connection, state, cleanup_deadline) do
              {:ok, state} ->
                {:reply, {:error, :enforcement_failed}, state}

              {:error, state} ->
                {:stop, :media_policy_enforcement_failed, {:error, :enforcement_failed}, state}
            end
        end
    end
  end

  defp register_group(_enforcers, _connection, _scope, state),
    do: {:reply, {:error, :invalid_enforcers}, state}

  @impl true
  def handle_info({:DOWN, monitor, :process, process, reason}, state) do
    private =
      Enum.find(state.enforcers, fn {_actor, registration} ->
        match?(%{private: %{monitor: ^monitor}}, registration)
      end)

    cond do
      private != nil ->
        retire_private(private, state)

      Map.get(state.connection_monitors, process) == monitor ->
        {:noreply, retire_connection(process, state)}

      true ->
        case Map.get(state.enforcers, process) do
          %{monitor: ^monitor, connection: connection, group: %MapSet{} = group} ->
            deadline = System.monotonic_time(:millisecond) + state.enforcement_timeout_ms

            case retire_enforcer_group(group, process, connection, state, deadline) do
              {:ok, state} -> {:noreply, state}
              {:error, state} -> {:stop, :media_policy_enforcement_failed, state}
            end

          %{monitor: ^monitor, connection: connection} ->
            if connection != nil and not Process.alive?(connection),
              do: {:noreply, retire_connection(connection, state)},
              else: {:stop, {:media_policy_enforcer_unavailable, process, reason}, state}

          _unknown ->
            {:noreply, state}
        end
    end
  end

  def handle_info({:private_enforcers_expired, token}, state) do
    case Enum.find(state.enforcers, fn {_actor, registration} ->
           match?(%{private: %{token: ^token}}, registration)
         end) do
      nil -> {:noreply, state}
      private -> retire_private(private, state)
    end
  end

  defp retire_private({_actor, %{group: group, connection: connection}}, state) do
    deadline = System.monotonic_time(:millisecond) + state.enforcement_timeout_ms

    case retire_enforcer_group(group, nil, connection, state, deadline) do
      {:ok, state} -> {:noreply, state}
      {:error, state} -> {:stop, :media_policy_enforcement_failed, state}
    end
  end

  defp monitor_enforcer(enforcer, connection, state) do
    monitor_enforcer(enforcer, connection, state, nil)
  end

  defp monitor_enforcer(enforcer, connection, state, group, private \\ nil) do
    if Map.has_key?(state.enforcers, enforcer) do
      state
    else
      connection_monitors =
        if connection == nil,
          do: state.connection_monitors,
          else:
            Map.put_new_lazy(state.connection_monitors, connection, fn ->
              Process.monitor(connection)
            end)

      registration = %{
        monitor: Process.monitor(enforcer),
        connection: connection,
        group: group,
        private: private
      }

      %{
        state
        | enforcers: Map.put(state.enforcers, enforcer, registration),
          connection_monitors: connection_monitors
      }
    end
  end

  defp retire_connection(connection, state) do
    {monitor, connection_monitors} = Map.pop(state.connection_monitors, connection)
    if monitor, do: Process.demonitor(monitor, [:flush])

    enforcers =
      Map.reject(state.enforcers, fn {_enforcer, registration} ->
        if registration.connection == connection do
          Process.demonitor(registration.monitor, [:flush])
          PrivateRegistration.release(Map.get(registration, :private))
          true
        else
          false
        end
      end)

    %{state | enforcers: enforcers, connection_monitors: connection_monitors}
  end

  defp retire_enforcers(connection, retiring, state) do
    retiring = retiring |> MapSet.new() |> expand_enforcer_groups(state.enforcers)

    enforcers =
      Map.reject(state.enforcers, fn {enforcer, registration} ->
        if registration.connection == connection and MapSet.member?(retiring, enforcer) do
          Process.demonitor(registration.monitor, [:flush])
          PrivateRegistration.release(Map.get(registration, :private))
          true
        else
          false
        end
      end)

    connection_monitors =
      if Enum.any?(enforcers, fn {_enforcer, registration} ->
           registration.connection == connection
         end) do
        state.connection_monitors
      else
        case Map.pop(state.connection_monitors, connection) do
          {nil, monitors} ->
            monitors

          {monitor, monitors} ->
            Process.demonitor(monitor, [:flush])
            monitors
        end
      end

    %{state | enforcers: enforcers, connection_monitors: connection_monitors}
  end

  defp expand_enforcer_groups(retiring, enforcers) do
    Enum.reduce(retiring, retiring, fn enforcer, expanded ->
      case Map.get(enforcers, enforcer) do
        %{group: %MapSet{} = group} -> MapSet.union(expanded, group)
        _individual_or_retired -> expanded
      end
    end)
  end

  defp retire_enforcer_group(group, failed, connection, state, deadline) do
    members =
      Enum.flat_map(group, fn enforcer ->
        case Map.get(state.enforcers, enforcer) do
          %{group: ^group, monitor: monitor} when enforcer != failed -> [{enforcer, monitor}]
          _failed_or_replaced -> []
        end
      end)

    Enum.each(members, fn {enforcer, _monitor} -> Process.exit(enforcer, :kill) end)

    case await_stopped(members, deadline) do
      :ok -> {:ok, retire_enforcers(connection, group, state)}
      {:error, :teardown_timeout} -> {:error, state}
    end
  end

  defp await_stopped([], _deadline), do: :ok

  defp await_stopped([{enforcer, monitor} | rest], deadline) do
    if Process.alive?(enforcer) do
      receive do
        {:DOWN, ^monitor, :process, ^enforcer, _reason} -> await_stopped(rest, deadline)
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          {:error, :teardown_timeout}
      end
    else
      await_stopped(rest, deadline)
    end
  end

  defp install_candidate(snapshot, deadline, new_enforcers, state) do
    remaining = deadline - System.monotonic_time(:millisecond)

    cond do
      remaining <= 0 ->
        {:reply, {:error, :deadline_elapsed}, state}

      snapshot == state.snapshot ->
        retain_candidate(new_enforcers, state)

      true ->
        enforce_candidate(snapshot, deadline, remaining, new_enforcers, state)
    end
  end

  defp retain_candidate(enforcers, state) do
    if Enum.all?(enforcers, &Map.has_key?(state.enforcers, enforcer_pid(&1))),
      do: {:reply, {:ok, state.snapshot}, state},
      else: {:reply, {:error, :unchanged_candidate}, state}
  end

  defp enforce_candidate(snapshot, deadline, remaining, new_enforcers, state) do
    state = %{state | enforcers: PrivateRegistration.promote(state.enforcers, new_enforcers)}

    state =
      Enum.reduce(new_enforcers, state, fn registration, state ->
        {enforcer, connection} = enforcer_connection(registration)
        monitor_enforcer(enforcer, connection, state)
      end)

    case apply_policy(state, snapshot, deadline, min(remaining, state.enforcement_timeout_ms)) do
      {:ok, state} ->
        contributions =
          Map.take(state.participant_policies, MapSet.to_list(snapshot.present_participant_ids))

        {:reply, {:ok, snapshot}, %{state | contributions: contributions, snapshot: snapshot}}

      {:error, state} ->
        # Some enforcers may have adopted already. An expired/failed commit cannot be recovered here.
        {:stop, :media_policy_enforcement_failed, {:error, :enforcement_failed}, state}
    end
  end

  defp validate_enforcers(enforcers) when is_list(enforcers) do
    if Enum.all?(enforcers, &valid_enforcer?/1),
      do: :ok,
      else: {:error, :invalid_enforcers}
  end

  defp validate_enforcers(_enforcers), do: {:error, :invalid_enforcers}

  defp valid_enforcer?({enforcer, connection}),
    do:
      is_pid(enforcer) and enforcer != self() and is_pid(connection) and
        Process.alive?(connection)

  defp valid_enforcer?(enforcer), do: is_pid(enforcer) and enforcer != self()

  defp enforcer_connection({enforcer, connection}), do: {enforcer, connection}
  defp enforcer_connection(enforcer), do: {enforcer, nil}

  defp enforcer_pid(registration), do: registration |> enforcer_connection() |> elem(0)

  defp commit(contributions, state) do
    present = contributions |> Map.keys() |> MapSet.new()

    case Candidate.new(self(), present, state) do
      {:ok, %Candidate{snapshot: snapshot}} ->
        deadline = System.monotonic_time(:millisecond) + state.enforcement_timeout_ms

        case apply_policy(state, snapshot, deadline, state.enforcement_timeout_ms) do
          {:ok, state} ->
            {:reply, {:ok, snapshot}, %{state | contributions: contributions, snapshot: snapshot}}

          {:error, state} ->
            {:stop, :media_policy_enforcement_failed, {:error, :enforcement_failed}, state}
        end

      {:error, _invalid_policy} ->
        {:stop, :invalid_policy, {:error, :invalid_policy}, state}
    end
  end

  defp apply_policy(state, snapshot, deadline, timeout) do
    deadline = min(deadline, System.monotonic_time(:millisecond) + timeout)

    with {:ok, state} <- retire_failed_groups(state, deadline) do
      apply_policy_enforcers(state, state.enforcers, snapshot, deadline)
    end
  end

  defp apply_policy_enforcers(state, enforcers, snapshot, deadline) do
    case Barrier.apply(enforcers, snapshot, remaining(deadline)) do
      :ok ->
        if System.monotonic_time(:millisecond) < deadline,
          do: {:ok, state},
          else: {:error, state}

      {:error, :enforcement_failed, failed, applied} ->
        continue_after_group_failure(
          state,
          enforcers,
          failed,
          applied,
          snapshot,
          deadline
        )
    end
  end

  defp continue_after_group_failure(
         state,
         enforcers,
         failed,
         applied,
         snapshot,
         deadline
       ) do
    case failed_enforcer_group(state, failed) do
      {:ok, group, dead, connection} ->
        with {:ok, state} <- retire_enforcer_group(group, dead, connection, state, deadline) do
          pending = Map.drop(enforcers, MapSet.to_list(MapSet.union(applied, group)))
          apply_policy_enforcers(state, pending, snapshot, deadline)
        end

      :error ->
        {:error, state}
    end
  end

  defp retire_failed_groups(state, deadline) do
    Enum.reduce_while(state.enforcers, {:ok, state}, fn {enforcer, _registration}, {:ok, state} ->
      case Map.get(state.enforcers, enforcer) do
        %{group: %MapSet{} = group, connection: connection} ->
          failed = Enum.find(group, &(not Process.alive?(&1)))

          active? =
            PrivateRegistration.active?(Map.get(Map.fetch!(state.enforcers, enforcer), :private))

          case {failed, active?} do
            {nil, true} ->
              {:cont, {:ok, state}}

            {failed, _active?} ->
              case retire_enforcer_group(group, failed, connection, state, deadline) do
                {:ok, state} -> {:cont, {:ok, state}}
                {:error, state} -> {:halt, {:error, state}}
              end
          end

        _not_grouped_or_retired ->
          {:cont, {:ok, state}}
      end
    end)
  end

  defp failed_enforcer_group(state, failed) do
    case Map.get(state.enforcers, failed) do
      %{group: %MapSet{} = group, connection: connection, private: private} when private != nil ->
        {:ok, group, Enum.find(group, &(not Process.alive?(&1))), connection}

      %{group: %MapSet{} = group, connection: connection} ->
        case Enum.find(group, &(not Process.alive?(&1))) do
          nil -> :error
          dead -> {:ok, group, dead, connection}
        end

      _individual_or_retired ->
        :error
    end
  end

  defp valid_enforcer_group?(group) do
    MapSet.size(group) > 0 and
      Enum.all?(group, &(is_pid(&1) and &1 != self() and Process.alive?(&1)))
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 1)

  defp participant_policies(participants) when is_map(participants) do
    Enum.reduce_while(participants, {:ok, %{}}, fn
      {_call_spec_key, %Participant{participant_id: participant_id, while_present: policy}},
      {:ok, policies}
      when is_binary(participant_id) ->
        if Map.has_key?(policies, participant_id) or not MediaPolicy.valid?(policy) do
          {:halt, {:error, :invalid_policy}}
        else
          {:cont, {:ok, Map.put(policies, participant_id, policy)}}
        end

      {_call_spec_key, _participant}, _acc ->
        {:halt, {:error, :invalid_policy}}
    end)
  end

  defp participant_policies(_participants), do: {:error, :invalid_policy}

  defp enforcement_timeout(options) do
    case Keyword.get(
           options,
           :media_policy_enforcement_timeout_ms,
           @default_enforcement_timeout_ms
         ) do
      timeout when is_integer(timeout) and timeout > 0 -> {:ok, timeout}
      _invalid -> {:error, :invalid_policy_enforcement_timeout}
    end
  end

  defp via(options) do
    options
    |> Keyword.fetch!(:incarnation_id)
    |> registry_key()
    |> then(&{:via, Registry, {Vxpipe.CallEngine.RoomRegistry, &1}})
  end

  defp registry_key(incarnation_id), do: {:media_policy_authority, incarnation_id}
end
