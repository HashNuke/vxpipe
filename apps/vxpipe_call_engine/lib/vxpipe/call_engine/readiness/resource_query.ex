defmodule Vxpipe.CallEngine.Readiness.ResourceQuery do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Readiness.Resource

  @adapters %{
    room_mixer: Vxpipe.CallEngine.RoomMixer,
    transcript_router: Vxpipe.CallEngine.TranscriptRouter,
    call_variables: Vxpipe.CallEngine.CallVariables,
    live_inspection: Vxpipe.CallEngine.LiveInspection.Buffer,
    archive: Vxpipe.CallEngine.Archive.Subscriber,
    recording: Vxpipe.CallEngine.RoomRecording,
    model_inference: Vxpipe.CallEngine.AgentRuntime.Coordinator,
    speech_to_speech: Vxpipe.CallEngine.Capability.SpeechToSpeech,
    text_to_speech: Vxpipe.CallEngine.Capability.TextToSpeech
  }

  def observe(kind, scope, instance, policy) when is_pid(instance) do
    adapter = Map.fetch!(@adapters, kind)

    with {:ok, resource, status} when status in [:ready, :preparing, :failed] <-
           adapter.readiness(instance),
         :ok <- validate(resource, kind, scope, instance, policy),
         false <- status == :failed do
      {:ok, resource}
    else
      {:error, %{kind: _kind}} = failure -> failure
      true -> failure(kind, scope, :failed)
      _unavailable -> failure(kind, scope, :unavailable)
    end
  rescue
    _exception -> failure(kind, scope, :unavailable)
  catch
    _kind, _reason -> failure(kind, scope, :unavailable)
  end

  def observe(kind, scope, _missing, _policy), do: failure(kind, scope, :missing)

  def validate(
        %Resource{kind: kind, scope: scope, instance: instance} = resource,
        kind,
        scope,
        instance,
        policy
      ) do
    cond do
      not Resource.bound?(resource) ->
        failure(kind, scope, :invalid_resource)

      resource.policy_interval != interval(kind, scope, policy) ->
        failure(kind, scope, :policy_not_prepared)

      true ->
        :ok
    end
  end

  def validate(_resource, kind, scope, _instance, _policy),
    do: failure(kind, scope, :invalid_resource)

  def failure(kind, scope, reason), do: {:error, %{kind: kind, scope: scope, reason: reason}}

  defp interval(:room_mixer, :room, policy),
    do: Map.take(policy.intervals, [:audio_input, :audio_output, :recording])

  defp interval(:transcript_router, :room, policy), do: policy.intervals.speech_to_text
  defp interval(:recording, :room, policy), do: Snapshot.interval(policy, :recording)
  defp interval(_kind, _scope, _policy), do: nil
end
