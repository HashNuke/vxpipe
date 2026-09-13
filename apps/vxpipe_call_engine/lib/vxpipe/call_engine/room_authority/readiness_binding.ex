defmodule Vxpipe.CallEngine.RoomAuthority.ReadinessBinding do
  @moduledoc false

  alias Vxpipe.CallEngine.{
    AgentActivationSupervisor,
    CallVariables,
    RoomCapabilitySupervisor,
    RoomRecording
  }

  alias Vxpipe.CallEngine.RoomAuthority.State

  @derive {Inspect, only: [:identity]}
  @enforce_keys [
    :identity,
    :owner,
    :policy_authority,
    :plan,
    :connections,
    :room,
    :participants,
    :options,
    :attempt
  ]
  defstruct @enforce_keys

  def options(options) do
    [
      recording: options |> Keyword.get(:recording, []) |> Keyword.take([:enabled, :targets]),
      archive?: Keyword.get(options, :archive_handoff) != nil,
      live_inspection?: Keyword.has_key?(options, :plan)
    ]
  end

  def capture(%State{participant_transfer_runtime: nil}), do: {:error, :unsupported_definition}

  def capture(%State{} = state) do
    plan = state.participant_transfer_runtime.plan

    identity = %{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      call_id: plan.call_id,
      incarnation_id: state.snapshot.incarnation_id
    }

    {:ok,
     %__MODULE__{
       identity: identity,
       owner: self(),
       policy_authority: state.media_policy_authority,
       plan: plan,
       connections:
         Map.new(state.connections, fn {id, connection} ->
           {id, connection_binding(connection)}
         end),
       room: room_bindings(state),
       participants: participant_bindings(plan, state),
       options: state.readiness_options,
       attempt: attempt(state.pending_participant_transfer)
     }}
  end

  defp connection_binding(connection) do
    connection
    |> Map.take([:participant_id, :pid, :role, :admission, :transfer_attempt_id, :output_sink])
    |> Map.put(:speech_to_text, speech_binding(connection.speech_to_text))
  end

  defp speech_binding(nil), do: nil
  defp speech_binding(speech), do: Map.take(speech, [:capability, :ingress])

  defp room_bindings(state) do
    incarnation = state.snapshot.incarnation_id

    %{
      room_mixer: state.room_mixer,
      transcript_router: state.transcript_router,
      call_variables: CallVariables.whereis(incarnation),
      recording: RoomRecording.whereis(incarnation),
      archive: archive(state.archive_recorder.port),
      live_inspection: inspection(state.archive_recorder.port)
    }
  end

  defp archive(%{handoff: %{subscriber: subscriber}}), do: subscriber
  defp archive(_port), do: nil
  defp inspection(%{live_inspection_port: %{buffer: buffer}}), do: buffer
  defp inspection(_port), do: nil

  defp participant_bindings(plan, state) do
    Map.new(plan.participants, fn {_key, participant} ->
      model =
        if participant.activation_id != nil,
          do: AgentActivationSupervisor.whereis_child(participant.activation_id, :coordinator)

      {participant.participant_id,
       %{
         model_inference: model,
         text_to_speech:
           RoomCapabilitySupervisor.whereis_text_to_speech(
             state.snapshot.incarnation_id,
             participant.participant_id
           )
       }}
    end)
  end

  defp attempt(%{attempt_id: id, deadline_ms: deadline}), do: %{id: id, deadline_ms: deadline}
  defp attempt(_pending), do: nil
end
