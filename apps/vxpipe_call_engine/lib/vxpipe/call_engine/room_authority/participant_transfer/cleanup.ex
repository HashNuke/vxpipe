defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Cleanup do
  @moduledoc false

  alias Vxpipe.CallEngine.{RoomCapabilitySupervisor, RoomParticipantSupervisor}
  alias Vxpipe.CallEngine.RoomAuthority.{ParticipantLifecycle, Startup, State}
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{HumanPreparation, Preparation}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @spec discard(Preparation.t(), State.t()) :: :ok
  def discard(%Preparation{} = preparation, %State{} = state) do
    _ = Startup.discard_text_to_speech(preparation.text_to_speech, state)
    _ = ParticipantLifecycle.discard(preparation.participant, state)
    :ok
  end

  @spec discard(HumanPreparation.t(), State.t()) :: :ok
  def discard(%HumanPreparation{} = preparation, %State{} = state) do
    _ = Startup.discard_text_to_speech(preparation.text_to_speech, state)
    :ok
  end

  @spec discard_destination(Request.t()) :: :ok
  def discard_destination(%Request{} = request) do
    _ =
      RoomCapabilitySupervisor.stop_text_to_speech(
        request.incarnation_id,
        request.destination_participant_id
      )

    _ =
      RoomParticipantSupervisor.stop_participant_by_id(
        request.incarnation_id,
        request.tenant_id,
        request.room_id,
        request.destination_participant_id
      )

    :ok
  end

  @spec discard_source_text_to_speech(Request.t()) :: :ok
  def discard_source_text_to_speech(%Request{} = request) do
    _ =
      RoomCapabilitySupervisor.stop_text_to_speech(
        request.incarnation_id,
        request.source_participant_id
      )

    :ok
  end
end
