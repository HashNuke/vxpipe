defmodule Vxpipe.CallEngine.MediaPolicy.PrivateRegistration do
  @moduledoc false

  @scope_keys [:owner, :attempt_id, :deadline_ms, :participant_id]

  def valid_scope?(scope, snapshot, participants) when is_map(scope) do
    with %{owner: owner, attempt_id: attempt, deadline_ms: deadline, participant_id: participant} <-
           scope do
      is_pid(owner) and owner != self() and Process.alive?(owner) and
        is_binary(attempt) and byte_size(attempt) in 1..128 and is_integer(deadline) and
        deadline > now() and Map.has_key?(participants, participant) and
        not MapSet.member?(snapshot.present_participant_ids, participant)
    else
      _invalid -> false
    end
  end

  def valid_scope?(_scope, _snapshot, _participants), do: false

  def start(nil), do: nil

  def start(scope) do
    token = make_ref()

    %{
      scope: Map.take(scope, @scope_keys),
      monitor: Process.monitor(scope.owner),
      token: token,
      timer:
        Process.send_after(
          self(),
          {:private_enforcers_expired, token},
          max(scope.deadline_ms - now(), 0)
        )
    }
  end

  def release(nil), do: :ok

  def release(lease) do
    Process.demonitor(lease.monitor, [:flush])
    Process.cancel_timer(lease.timer)
    :ok
  end

  def active?(nil), do: true
  def active?(lease), do: lease.scope.deadline_ms > now() and Process.alive?(lease.scope.owner)

  def validate_selection(enforcers, selected, scope, deadline, candidate) do
    selected_pids = MapSet.new(selected, &pid/1)

    valid? =
      Enum.all?(selected, fn selection ->
        case Map.get(enforcers, pid(selection)) do
          %{private: %{scope: expected} = lease, connection: connection, group: group} ->
            is_map(scope) and Map.take(scope, @scope_keys) == expected and
              deadline == expected.deadline_ms and active?(lease) and
              selection == {pid(selection), connection} and Process.alive?(pid(selection)) and
              MapSet.subset?(group, selected_pids) and
              MapSet.member?(candidate.snapshot.present_participant_ids, expected.participant_id) and
              not MapSet.member?(
                candidate.base_snapshot.present_participant_ids,
                expected.participant_id
              )

          nil ->
            # Scoped receipts are inventories of registered actors, not authority
            # to register missing (possibly retired) identities as ordinary ones.
            scope == nil

          _ordinary ->
            scope == nil
        end
      end)

    complete? =
      Enum.all?(enforcers, fn
        {actor, %{private: %{scope: private_scope}}} ->
          not MapSet.member?(
            candidate.snapshot.present_participant_ids,
            private_scope.participant_id
          ) or
            MapSet.member?(selected_pids, actor)

        _ordinary ->
          true
      end)

    if valid? and complete?, do: :ok, else: {:error, :invalid_private_enforcers}
  end

  def admission_available?(enforcers, participant) do
    not Enum.any?(enforcers, fn
      {_actor, %{private: %{scope: %{participant_id: ^participant}}}} -> true
      _ordinary -> false
    end)
  end

  def promote(enforcers, selected) do
    Enum.reduce(selected, enforcers, fn selection, enforcers ->
      case Map.get(enforcers, pid(selection)) do
        %{private: lease} = registration when lease != nil ->
          release(lease)
          Map.put(enforcers, pid(selection), %{registration | private: nil, group: nil})

        _ordinary ->
          enforcers
      end
    end)
  end

  defp pid({pid, _connection}), do: pid
  defp pid(pid), do: pid
  defp now, do: System.monotonic_time(:millisecond)
end
