defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.DestinationPreparer do
  @moduledoc false

  alias Vxpipe.CallEngine.PlanStartup
  alias Vxpipe.CallEngine.PlanStartup.{AgentDestination, HumanDestination}
  alias Vxpipe.CallEngine.ResolvedCallPlan.Participant
  alias Vxpipe.CallEngine.RoomAuthority.{ParticipantLifecycle, ParticipantPreparation, Startup}

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{
    HumanPreparation,
    Preparation,
    Runtime
  }

  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @type failure_reason ::
          :destination_participant_unavailable
          | :destination_plan_unavailable
          | :destination_text_to_speech_unavailable

  @spec prepare(
          Request.t(),
          Runtime.t(),
          Participant.t(),
          boolean(),
          [Vxpipe.AgentRuntime.Message.t()],
          nil | Vxpipe.CallEngine.TextToSpeechRuntime.t()
        ) ::
          {:ok, Preparation.t() | HumanPreparation.t()} | {:error, failure_reason()}
  def prepare(
        %Request{} = request,
        %Runtime{} = runtime,
        %Participant{} = participant,
        first_activation?,
        initial_messages,
        source_text_to_speech
      )
      when is_boolean(first_activation?) and is_list(initial_messages) do
    case participant.kind do
      :agent ->
        prepare_agent(request, runtime, participant, first_activation?, initial_messages)

      :human ->
        prepare_human(request, runtime, participant, source_text_to_speech)
    end
  end

  defp prepare_agent(request, runtime, participant, first_activation?, initial_messages) do
    case agent_destination(request, runtime, participant, initial_messages) do
      {:ok, %AgentDestination{} = destination} ->
        prepare_participant(request, runtime, destination, first_activation?)

      {:error, _reason} ->
        {:error, :destination_plan_unavailable}
    end
  end

  defp prepare_human(request, runtime, participant, source_text_to_speech) do
    with %Vxpipe.CallEngine.TextToSpeechRuntime{} <- source_text_to_speech,
         {:ok, %HumanDestination{} = destination} <-
           PlanStartup.human_destination(runtime.plan, participant),
         {:ok, text_to_speech} <-
           Startup.prepare_text_to_speech(
             source_text_to_speech,
             participant.participant_id,
             request.incarnation_id,
             Keyword.fetch!(runtime.startup_options, :owner)
           ) do
      {:ok, %HumanPreparation{destination: destination, text_to_speech: text_to_speech}}
    else
      nil -> {:error, :destination_text_to_speech_unavailable}
      {:error, %Vxpipe.CallEngine.Error{}} -> {:error, :destination_plan_unavailable}
      {:error, _reason} -> {:error, :destination_text_to_speech_unavailable}
    end
  end

  defp prepare_participant(request, runtime, destination, first_activation?) do
    case ParticipantLifecycle.prepare(
           destination.command,
           request.incarnation_id,
           agent_activation: destination.agent_activation
         ) do
      {:ok, %ParticipantPreparation{} = participant} ->
        prepare_text_to_speech(
          request,
          runtime,
          destination,
          participant,
          first_activation?
        )

      {:error, _reason} ->
        {:error, :destination_participant_unavailable}
    end
  end

  defp agent_destination(request, runtime, participant, initial_messages) do
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
        {:error, :destination_text_to_speech_unavailable}
    end
  end
end
