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

  alias Vxpipe.CallEngine.Guardrails.TransferAdmission

  @type entry :: %{
          invocation_id: String.t(),
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

  @spec bind(map(), entry()) :: map()
  def bind(%{transfer_verdicts: verdicts} = state, %{invocation_id: id, verdict: :passed} = entry)
      when is_binary(id) and id != "" do
    if valid_entry?(entry) do
      %{state | transfer_verdicts: Map.put(verdicts, id, entry)}
    else
      state
    end
  end

  def bind(%{} = state, _entry), do: state

  @spec consume(map(), map()) ::
          {:ok, map(), map()} | {:error, :stale | :unchecked, map()}
  def consume(%{} = state, %{} = request) do
    case current_policy(state, request) do
      nil ->
        {:ok, request, state}

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
        case get_entry(state, request.tool_call_id) do
          nil ->
            {:error, :unchecked}

          stored ->
            if entry_fresh?(stored, request, policy), do: {:ok, stored}, else: {:error, :stale}
        end
    end
  end

  @spec delete(map(), String.t()) :: map()
  def delete(%{transfer_verdicts: verdicts} = state, invocation_id)
      when is_binary(invocation_id) do
    %{state | transfer_verdicts: Map.delete(verdicts, invocation_id)}
  end

  def delete(%{} = state, _invocation_id), do: state

  @spec drop_for_source(map(), String.t()) :: map()
  def drop_for_source(%{transfer_verdicts: verdicts} = state, activation_id)
      when is_binary(activation_id) do
    kept =
      Map.reject(verdicts, fn {_id, entry} ->
        match?(%{source_activation_id: ^activation_id}, entry)
      end)

    %{state | transfer_verdicts: kept}
  end

  def drop_for_source(%{} = state, _activation_id), do: state

  @spec drop_for_participant(map(), String.t() | nil) :: map()
  def drop_for_participant(%{transfer_verdicts: verdicts} = state, participant_id)
      when is_binary(participant_id) do
    kept =
      Map.reject(verdicts, fn {_id, entry} ->
        match?(%{source_participant_id: ^participant_id}, entry)
      end)

    %{state | transfer_verdicts: kept}
  end

  def drop_for_participant(%{} = state, _participant_id), do: state

  @spec peek(map(), String.t()) :: {:ok, entry()} | :empty
  def peek(%{} = state, invocation_id) when is_binary(invocation_id) do
    case get_entry(state, invocation_id) do
      nil -> :empty
      entry -> {:ok, entry}
    end
  end

  def peek(_state, _invocation_id), do: :empty

  defp consume_guarded(state, request, policy) do
    invocation_id = request.tool_call_id
    stored = get_entry(state, invocation_id)

    cond do
      stored != nil and entry_fresh?(stored, request, policy) ->
        state = delete_entry(state, invocation_id)
        {:ok, stamp_request(request, stored), state}

      stored != nil ->
        {:error, :stale, delete_entry(state, invocation_id)}

      true ->
        {:error, :unchecked, state}
    end
  end

  defp get_entry(%{transfer_verdicts: verdicts}, invocation_id) when is_binary(invocation_id) do
    Map.get(verdicts, invocation_id)
  end

  defp get_entry(_state, _invocation_id), do: nil

  defp delete_entry(%{transfer_verdicts: verdicts} = state, invocation_id) do
    %{state | transfer_verdicts: Map.delete(verdicts, invocation_id)}
  end

  defp entry_fresh?(%{verdict: :passed} = entry, request, {revision, digest}) do
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
    is_binary(entry[:source_activation_id]) and
      is_binary(entry[:source_participant_id]) and
      is_binary(entry[:destination_call_spec_key]) and
      is_binary(entry[:policy_digest]) and
      is_integer(entry[:policy_revision]) and entry.policy_revision >= 0 and
      is_binary(entry[:incarnation_id]) and
      is_integer(entry[:checked_at_ms]) and
      entry[:source] in [:bound, :checked]
  end
end
