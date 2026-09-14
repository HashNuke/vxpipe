defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.HumanBriefing do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.TextToSpeech
  alias Vxpipe.CallEngine.{Id, Telemetry, TextToSpeechRequest}
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{HumanPreparation, Pending}
  alias Vxpipe.CallEngine.RoomAuthority.{Startup, State}

  @spec start(Pending.t(), HumanPreparation.t(), map(), State.t()) ::
          {:ok, TextToSpeechRequest.t()} | {:error, :unavailable}
  def start(
        %Pending{} = pending,
        %HumanPreparation{} = preparation,
        connection,
        %State{}
      ) do
    request = %TextToSpeechRequest{
      tenant_id: pending.request.tenant_id,
      room_id: pending.request.room_id,
      incarnation_id: pending.request.incarnation_id,
      participant_id: pending.request.destination_participant_id,
      source_participant_id: pending.request.destination_participant_id,
      connection_id: connection.attach_command.connection_id,
      command_id: pending.request.command_id,
      correlation_id: pending.request.correlation_id,
      output_id: Id.generate(:event),
      output_sink: connection.output_sink,
      purpose: :transfer_briefing,
      source_policy: %{},
      text: text(pending, preparation)
    }

    case TextToSpeech.synthesize(preparation.text_to_speech.pid, request) do
      :ok -> {:ok, request}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  @spec matches?(Pending.t(), pid(), TextToSpeechRequest.t()) :: boolean()
  def matches?(
        %Pending{preparation: %HumanPreparation{} = preparation, briefing_request: expected},
        capability,
        %TextToSpeechRequest{} = request
      ) do
    preparation.text_to_speech != nil and
      preparation.text_to_speech.pid == capability and expected == request
  end

  @spec complete(Pending.t(), State.t()) :: Pending.t()
  def complete(%Pending{} = pending, %State{} = state) do
    pending = stop_timing(pending, :ok)
    _ = Startup.discard_text_to_speech(pending.preparation.text_to_speech, state)
    preparation = %{pending.preparation | text_to_speech: nil}

    %{
      pending
      | preparation: preparation,
        briefing: :completed,
        briefing_request: nil,
        acceptance_started_at: Telemetry.started_at()
    }
  end

  def stop_timing(%Pending{} = pending, outcome) do
    for {phase, started_at} <- [
          briefing: pending.briefing_started_at,
          acceptance: pending.acceptance_started_at
        ],
        is_integer(started_at) do
      Telemetry.transfer_phase_stop(started_at, phase, outcome)
    end

    %{pending | briefing_started_at: nil, acceptance_started_at: nil}
  end

  defp text(pending, preparation) do
    notice = preparation.destination.participant.transfer_notice

    [pending.request.reason, notice]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
