defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.HumanDestinationPreparer do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.TextToSpeech
  alias Vxpipe.CallEngine.PlanStartup
  alias Vxpipe.CallEngine.PlanStartup.HumanDestination
  alias Vxpipe.CallEngine.ResolvedCallPlan.Participant
  alias Vxpipe.CallEngine.RoomCapabilitySupervisor
  alias Vxpipe.CallEngine.RoomAuthority.Startup
  alias Vxpipe.CallEngine.Telephony.{OutboundLegConnector, OutboundLegRequestResolver}

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{HumanPreparation, Runtime}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @type failure_reason ::
          :destination_connection_unavailable
          | :destination_plan_unavailable
          | :destination_text_to_speech_unavailable

  @spec prepare(
          Request.t(),
          Runtime.t(),
          Participant.t(),
          nil | Vxpipe.CallEngine.TextToSpeechRuntime.t(),
          integer()
        ) :: {:ok, HumanPreparation.t()} | {:error, failure_reason()}
  def prepare(
        %Request{} = request,
        %Runtime{} = runtime,
        %Participant{} = participant,
        source_text_to_speech,
        deadline_ms
      )
      when is_integer(deadline_ms) do
    with %Vxpipe.CallEngine.TextToSpeechRuntime{} <- source_text_to_speech,
         {:ok, %HumanDestination{} = destination} <-
           PlanStartup.human_destination(runtime.plan, participant, runtime.startup_options),
         {:ok, source_text_to_speech} <- Runtime.source_text_to_speech(runtime, request),
         {:ok, outbound_leg} <-
           prepare_connection(runtime, participant, request.incarnation_id, deadline_ms) do
      prepare_text_to_speech(
        request,
        runtime,
        participant,
        destination,
        source_text_to_speech,
        outbound_leg,
        deadline_ms
      )
    else
      nil ->
        {:error, :destination_text_to_speech_unavailable}

      {:error, :source_text_to_speech_unavailable} ->
        {:error, :destination_text_to_speech_unavailable}

      {:error, %Vxpipe.CallEngine.Error{}} ->
        {:error, :destination_plan_unavailable}

      {:error, _reason} ->
        {:error, :destination_connection_unavailable}
    end
  end

  defp prepare_text_to_speech(
         request,
         runtime,
         participant,
         destination,
         source_text_to_speech,
         outbound_leg,
         deadline_ms
       ) do
    result =
      with {:ok, text_to_speech} <-
             Startup.prepare_text_to_speech(
               source_text_to_speech,
               participant.participant_id,
               request.incarnation_id,
               Keyword.fetch!(runtime.startup_options, :owner)
             ),
           :ok <- await_text_to_speech(text_to_speech, request, deadline_ms) do
        {:ok,
         %HumanPreparation{
           destination: destination,
           outbound_leg: outbound_leg,
           text_to_speech: text_to_speech
         }}
      else
        {:error, reason, text_to_speech} ->
          _ =
            RoomCapabilitySupervisor.stop_capability(
              request.incarnation_id,
              text_to_speech.pid
            )

          {:error, reason}

        {:error, _reason} = error ->
          error
      end

    case result do
      {:ok, %HumanPreparation{}} = prepared ->
        prepared

      {:error, _reason} ->
        if outbound_leg, do: OutboundLegConnector.disconnect(outbound_leg)
        {:error, :destination_text_to_speech_unavailable}
    end
  end

  defp await_text_to_speech(text_to_speech, request, deadline_ms) do
    case TextToSpeech.readiness(text_to_speech.pid) do
      {:ok, _resource, :ready} ->
        :ok

      {:ok, resource, :preparing} ->
        await_text_to_speech_resource(text_to_speech, resource, request, deadline_ms)

      _failed ->
        {:error, :text_to_speech_unavailable, text_to_speech}
    end
  end

  defp await_text_to_speech_resource(text_to_speech, resource, request, deadline_ms) do
    options = [
      owner: self(),
      attempt_id: request.tool_call_id <> ":private-text-to-speech",
      deadline_ms: deadline_ms,
      resources: [resource]
    ]

    case RoomCapabilitySupervisor.start_readiness(request.incarnation_id, options) do
      {:ok, collector} ->
        try do
          await_collector(collector, text_to_speech, deadline_ms)
        after
          _ = RoomCapabilitySupervisor.stop_capability(request.incarnation_id, collector)
        end

      {:error, _reason} ->
        {:error, :text_to_speech_unavailable, text_to_speech}
    end
  end

  defp await_collector(collector, text_to_speech, deadline_ms) do
    receive do
      {:vxpipe_readiness_changed, ^collector, %{status: :ready}} ->
        :ok

      {:vxpipe_readiness_changed, ^collector, %{status: :failed}} ->
        {:error, :text_to_speech_unavailable, text_to_speech}

      {:vxpipe_readiness_changed, ^collector, _preparing} ->
        await_collector(collector, text_to_speech, deadline_ms)
    after
      remaining(deadline_ms) ->
        {:error, :text_to_speech_unavailable, text_to_speech}
    end
  end

  defp prepare_connection(
         _runtime,
         %Participant{connection: %{service: :web}},
         _incarnation_id,
         _deadline_ms
       ) do
    {:ok, nil}
  end

  defp prepare_connection(runtime, participant, incarnation_id, deadline_ms) do
    remaining_ms = remaining(deadline_ms)

    with true <- remaining_ms > 0,
         {:ok, request} <-
           OutboundLegRequestResolver.resolve(runtime.plan, participant, incarnation_id) do
      OutboundLegConnector.connect(
        Keyword.get(runtime.startup_options, :outbound_leg_connector),
        request,
        remaining_ms
      )
    else
      false -> {:error, :outbound_connection_unavailable}
      {:error, _reason} = error -> error
    end
  end

  defp remaining(deadline_ms),
    do: max(deadline_ms - System.monotonic_time(:millisecond), 0)
end
