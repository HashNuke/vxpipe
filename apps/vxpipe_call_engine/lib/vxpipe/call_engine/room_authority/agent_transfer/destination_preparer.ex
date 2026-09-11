defmodule Vxpipe.CallEngine.RoomAuthority.AgentTransfer.DestinationPreparer do
  @moduledoc false

  alias Vxpipe.CallEngine.PlanStartup
  alias Vxpipe.CallEngine.PlanStartup.AgentDestination
  alias Vxpipe.CallEngine.ResolvedCallPlan.Participant
  alias Vxpipe.CallEngine.RoomAuthority.{ParticipantLifecycle, ParticipantPreparation, Startup}
  alias Vxpipe.CallEngine.RoomAuthority.AgentTransfer.{Preparation, Runtime}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @spec prepare(
          Request.t(),
          Runtime.t(),
          Participant.t(),
          boolean(),
          [Vxpipe.AgentRuntime.Message.t()]
        ) ::
          {:ok, Preparation.t()} | {:error, :unavailable}
  def prepare(
        %Request{} = request,
        %Runtime{} = runtime,
        %Participant{} = participant,
        first_activation?,
        initial_messages
      )
      when is_boolean(first_activation?) and is_list(initial_messages) do
    with {:ok, %AgentDestination{} = destination} <-
           destination(request, runtime, participant, initial_messages),
         {:ok, %ParticipantPreparation{} = participant} <-
           ParticipantLifecycle.prepare(
             destination.command,
             request.incarnation_id,
             agent_activation: destination.agent_activation
           ) do
      prepare_text_to_speech(
        request,
        runtime,
        destination,
        participant,
        first_activation?
      )
    else
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  defp destination(request, runtime, participant, initial_messages) do
    options =
      runtime.startup_options
      |> Keyword.put(:initial_messages, initial_messages)
      |> Keyword.put(:transfer_reason, request.reason)

    PlanStartup.agent_destination(
      runtime.plan,
      participant,
      options
    )
  end

  defp prepare_text_to_speech(
         request,
         runtime,
         destination,
         participant,
         first_activation?
       ) do
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
           text_to_speech: text_to_speech,
           first_activation?: first_activation?
         }}

      {:error, _reason} ->
        _ = ParticipantLifecycle.discard(participant, request.incarnation_id)
        {:error, :unavailable}
    end
  end
end
