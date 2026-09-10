defmodule Vxpipe.CallEngine.RoomAuthority.AgentTransfer.DestinationPreparer do
  @moduledoc false

  alias Vxpipe.CallEngine.PlanStartup
  alias Vxpipe.CallEngine.PlanStartup.AgentDestination
  alias Vxpipe.CallEngine.RoomAuthority.{ParticipantLifecycle, ParticipantPreparation, Startup}
  alias Vxpipe.CallEngine.RoomAuthority.AgentTransfer.{Preparation, Runtime}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @spec prepare(Request.t(), Runtime.t()) ::
          {:ok, Preparation.t()} | {:error, :unavailable}
  def prepare(%Request{} = request, %Runtime{} = runtime) do
    with {:ok, %AgentDestination{} = destination} <- destination(request, runtime),
         {:ok, %ParticipantPreparation{} = participant} <-
           ParticipantLifecycle.prepare(
             destination.command,
             request.incarnation_id,
             agent_activation: destination.agent_activation
           ) do
      prepare_text_to_speech(request, runtime, destination, participant)
    else
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  defp destination(request, runtime) do
    participant = Map.fetch!(runtime.plan.participants, request.destination_definition_key)
    PlanStartup.agent_destination(runtime.plan, participant, runtime.startup_options)
  end

  defp prepare_text_to_speech(request, runtime, destination, participant) do
    owner = Keyword.fetch!(runtime.startup_options, :owner)

    case Startup.prepare_text_to_speech(
           destination.text_to_speech,
           destination.participant.participant_id,
           request.incarnation_id,
           owner
         ) do
      {:ok, text_to_speech} ->
        {:ok,
         %Preparation{
           destination: destination,
           participant: participant,
           text_to_speech: text_to_speech
         }}

      {:error, _reason} ->
        _ = ParticipantLifecycle.discard(participant, request.incarnation_id)
        {:error, :unavailable}
    end
  end
end
