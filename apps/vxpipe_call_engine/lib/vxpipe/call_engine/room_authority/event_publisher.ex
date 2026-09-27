defmodule Vxpipe.CallEngine.RoomAuthority.EventPublisher do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.RoomAuthority.State
  alias Vxpipe.CallEngine.TranscriptRouter
  alias Vxpipe.CallEngine.TranscriptRouter.{Decision, Projection}

  @spec publish(State.t(), pid(), struct(), keyword()) :: State.t()
  def publish(%State{} = state, subscriber, event, attributes \\ [])
      when is_pid(subscriber) and is_list(attributes) do
    send(subscriber, {:vxpipe_event, event})
    archive_recorder = Recorder.event(state.archive_recorder, event, attributes)
    %{state | archive_recorder: archive_recorder}
  end

  @spec publish_transcript(State.t(), pid(), struct(), keyword()) :: {State.t(), map()}
  def publish_transcript(%State{} = state, fallback_subscriber, event, attributes \\ [])
      when is_pid(fallback_subscriber) and is_list(attributes) do
    {state, source_policy, _recipients} =
      publish_transcript_with_recipients(state, fallback_subscriber, event, attributes)

    {state, source_policy}
  end

  @spec publish_transcript_with_recipients(State.t(), pid(), struct(), keyword()) ::
          {State.t(), map(), MapSet.t(String.t()) | :legacy}
  def publish_transcript_with_recipients(
        %State{} = state,
        fallback_subscriber,
        event,
        attributes \\ []
      )
      when is_pid(fallback_subscriber) and is_list(attributes) do
    {policy_revision, attributes} =
      Keyword.pop(attributes, :media_policy_revision, :current)

    {virtual_recipient, attributes} =
      Keyword.pop(attributes, :virtual_recipient_participant_id)

    recipients = recipient_participant_ids(state)

    recipients =
      if is_binary(virtual_recipient),
        do: MapSet.put(recipients, virtual_recipient),
        else: recipients

    case transcript_decision(state, event.participant_id, policy_revision, recipients) do
      {:ok, %Decision{} = decision} ->
        send_recipients(state.connections, decision.recipient_participant_ids, event)

        attributes = Keyword.put(attributes, :source_policy, decision.source_policy)
        archive_recorder = Recorder.event(state.archive_recorder, event, attributes)

        {%{state | archive_recorder: archive_recorder}, decision.source_policy,
         decision.recipient_participant_ids}

      :legacy ->
        send(fallback_subscriber, {:vxpipe_event, event})
        archive_recorder = Recorder.event(state.archive_recorder, event, attributes)
        {%{state | archive_recorder: archive_recorder}, %{}, :legacy}

      {:error, _reason} ->
        source_policy = %{"save_transcripts" => false}
        attributes = Keyword.put(attributes, :source_policy, source_policy)
        archive_recorder = Recorder.event(state.archive_recorder, event, attributes)
        {%{state | archive_recorder: archive_recorder}, source_policy, MapSet.new()}
    end
  end

  @spec transcript_source_policy(State.t(), String.t()) :: map()
  def transcript_source_policy(%State{} = state, source_participant_id)
      when is_binary(source_participant_id) do
    source_policy(state, source_participant_id, :current)
  end

  @spec transcript_source_policy(State.t(), String.t(), non_neg_integer()) :: map()
  def transcript_source_policy(%State{} = state, source_participant_id, policy_revision)
      when is_binary(source_participant_id) and is_integer(policy_revision) and
             policy_revision >= 0 do
    source_policy(state, source_participant_id, policy_revision)
  end

  defp source_policy(state, source_participant_id, policy_revision) do
    case transcript_decision(state, source_participant_id, policy_revision) do
      {:ok, %Decision{} = decision} -> decision.source_policy
      :legacy -> %{}
      {:error, _reason} -> %{"save_transcripts" => false}
    end
  end

  defp transcript_decision(state, source_participant_id, revision),
    do:
      transcript_decision(
        state,
        source_participant_id,
        revision,
        recipient_participant_ids(state)
      )

  defp transcript_decision(
         %State{transcript_router: nil},
         _source_participant_id,
         _revision,
         _recipients
       ),
       do: :legacy

  defp transcript_decision(%State{} = state, source_participant_id, :current, recipients) do
    TranscriptRouter.project_current(
      state.transcript_router,
      source_participant_id,
      recipients
    )
  end

  defp transcript_decision(%State{} = state, source_participant_id, policy_revision, recipients) do
    projection = %Projection{
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      source_participant_id: source_participant_id,
      policy_revision: policy_revision,
      recipient_participant_ids: recipients
    }

    TranscriptRouter.project(state.transcript_router, projection)
  end

  defp recipient_participant_ids(state) do
    state.connections
    |> Map.values()
    |> Enum.map(& &1.participant_id)
    |> MapSet.new()
  end

  defp send_recipients(connections, recipient_participant_ids, event) do
    Enum.each(connections, fn {_connection_id, connection} ->
      if MapSet.member?(recipient_participant_ids, connection.participant_id) do
        send(connection.pid, {:vxpipe_event, event})
      end
    end)
  end
end
