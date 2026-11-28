defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Verdicts do
  @moduledoc false

  # Invocation-bound Before-outgoing-transfer verdicts shared between the
  # joint admission path, the worker execution gate and the room/announcement
  # paths. Entries and request stamps are passed-only by construction: a
  # blocked check never reaches the room, so denial lines cannot leak through
  # this store. Only room entries authorize execution; request stamps are
  # inspection markers written when an entry is consumed and carry no
  # authority on their own. Consume validates incarnation, source activation,
  # source participant, destination, policy revision and digest, then deletes the entry.
  # Permission authorization stays with Authorizer at begin/resume time.

  alias Vxpipe.CallEngine.Guardrails.{Deadline, TransferAdmission}

  @type entry :: %{
          invocation_id: String.t(),
          command_id: String.t(),
          expires_at_ms: integer(),
          verdict: :passed,
          source_activation_id: String.t(),
          source_participant_id: String.t(),
          destination_call_spec_key: String.t(),
          policy_digest: binary(),
          policy_revision: non_neg_integer(),
          incarnation_id: String.t(),
          checked_at_ms: integer(),
          source: :bound | :checked
        }

  def bind(%{transfer_verdicts: _} = state, %{verdict: :passed} = entry) do
    if valid_entry?(entry) and open?(entry) do
      key = {entry.command_id, entry.invocation_id}

      state =
        drop_matching(state, fn existing ->
          existing.source_activation_id == entry.source_activation_id and
            existing.command_id != entry.command_id
        end)

      state = delete_entry(state, key)
      delay = max(entry.expires_at_ms - System.monotonic_time(:millisecond), 0)
      timer = :erlang.start_timer(delay, self(), {:transfer_verdict, key})
      entry = Map.put(entry, :expiry_timer, timer)
      {:ok, %{state | transfer_verdicts: Map.put(state.transfer_verdicts, key, entry)}}
    else
      {:error, :invalid_verdict}
    end
  end

  def bind(_state, _entry), do: {:error, :invalid_verdict}

  @spec consume(map(), map()) ::
          {:ok, map(), map()} | {:error, :stale | :unchecked, map()}
  def consume(%{} = state, %{} = request) do
    case current_policy(state, request) do
      nil ->
        key = {request.command_id, request.tool_call_id}

        if get_entry(state, key),
          do: {:error, :stale, delete_entry(state, key)},
          else: {:ok, request, state}

      policy ->
        consume_guarded(state, request, policy)
    end
  end

  @spec validate(map(), map()) :: {:ok, entry()} | {:error, :stale | :unchecked}
  def validate(%{} = state, %{} = request) do
    case current_policy(state, request) do
      nil ->
        {:error, :unchecked}

      policy ->
        case get_entry(state, {request.command_id, request.tool_call_id}) do
          nil ->
            {:error, :unchecked}

          stored ->
            if open?(stored) and entry_fresh?(stored, request, policy),
              do: {:ok, stored},
              else: {:error, :stale}
        end
    end
  end

  def drop_for_source(state, activation),
    do: drop_matching(state, &(&1.source_activation_id == activation))

  def drop_for_participant(state, participant),
    do: drop_matching(state, &(&1.source_participant_id == participant))

  def drop_for_command(state, command), do: drop_matching(state, &(&1.command_id == command))

  defp drop_matching(state, predicate) do
    Enum.reduce(state.transfer_verdicts, state, fn {key, entry}, acc ->
      if predicate.(entry), do: delete_entry(acc, key), else: acc
    end)
  end

  def peek(state, key) do
    with %{} = entry <- get_entry(state, key),
         true <- open?(entry) do
      {:ok, Map.delete(entry, :expiry_timer)}
    else
      _ -> :empty
    end
  end

  def expire(state, key, timer) do
    case get_entry(state, key) do
      %{expiry_timer: ^timer} -> delete_entry(state, key)
      _ -> state
    end
  end

  defp consume_guarded(state, request, policy) do
    key = {request.command_id, request.tool_call_id}

    case get_entry(state, key) do
      nil ->
        {:error, :unchecked, state}

      entry ->
        state = delete_entry(state, key)

        if open?(entry) and entry_fresh?(entry, request, policy),
          do: {:ok, stamp_request(request, Map.delete(entry, :expiry_timer)), state},
          else: {:error, :stale, state}
    end
  end

  defp get_entry(state, key), do: Map.get(state.transfer_verdicts, key)
  defp open?(entry), do: System.monotonic_time(:millisecond) < entry.expires_at_ms

  defp delete_entry(state, key) do
    case Map.pop(state.transfer_verdicts, key) do
      {nil, _} ->
        state

      {%{expiry_timer: timer}, remaining} ->
        Process.cancel_timer(timer)
        %{state | transfer_verdicts: remaining}
    end
  end

  defp entry_fresh?(%{verdict: :passed} = entry, request, {revision, digest}) do
    entry.command_id == request.command_id and
      entry.incarnation_id == request.incarnation_id and
      entry.source_activation_id == request.source_activation_id and
      entry.source_participant_id == request.source_participant_id and
      entry.destination_call_spec_key == request.destination_call_spec_key and
      entry.policy_digest == digest and entry.policy_revision == revision
  end

  defp entry_fresh?(_entry, _request, _digest), do: false

  defp stamp_request(request, entry), do: %{request | transfer_admission: entry}

  @doc "Revalidates a room-owned admitted request after protected playback."
  def current_after_announcement?(state, request) do
    case current_policy(state, request) do
      nil ->
        request.transfer_admission == nil

      policy ->
        case request.transfer_admission do
          %{invocation_id: invocation} = entry when invocation == request.tool_call_id ->
            entry_fresh?(entry, request, policy)

          _ ->
            false
        end
    end
  end

  defp current_policy(state, request) do
    with %{participant_transfer_runtime: %{plan: %{participants: participants} = plan}} <- state,
         %{guardrails: guardrails} <- Map.get(participants, request.source_call_spec_key, %{}),
         questions when is_list(questions) <- guardrails_before_transfer(guardrails),
         digest when is_binary(digest) <- TransferAdmission.policy_digest(questions) do
      {Map.get(plan, :call_spec_revision), digest}
    else
      _unavailable -> nil
    end
  end

  defp guardrails_before_transfer(%{before_outgoing_transfer: questions}), do: questions
  defp guardrails_before_transfer(_guardrails), do: []

  defp valid_entry?(entry) do
    identifiers = [
      :command_id,
      :invocation_id,
      :source_activation_id,
      :source_participant_id,
      :destination_call_spec_key,
      :incarnation_id
    ]

    Enum.all?(identifiers, fn key -> is_binary(entry[key]) and byte_size(entry[key]) > 0 end) and
      is_binary(entry[:policy_digest]) and
      is_integer(entry[:policy_revision]) and entry.policy_revision >= 0 and
      is_integer(entry[:checked_at_ms]) and is_integer(entry[:expires_at_ms]) and
      entry.expires_at_ms <= Deadline.response(%{}) and
      entry[:source] in [:bound, :checked]
  end
end
