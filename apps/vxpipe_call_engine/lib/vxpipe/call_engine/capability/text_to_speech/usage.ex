defmodule Vxpipe.CallEngine.Capability.TextToSpeech.Usage do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.{Audio, Event, TTSUsage}
  alias Vxpipe.CallEngine.TextToSpeechRequest
  alias Vxpipe.CallEngine.Usage.{ProviderContext, TextToSpeechAttempt}
  alias Vxpipe.CallEngine.Id

  @spec start(TextToSpeechRequest.t(), nil | keyword(), map()) :: nil | TextToSpeechAttempt.t()
  def start(%TextToSpeechRequest{} = request, context, media_format) do
    with context when is_list(context) <- context,
         call_id when is_binary(call_id) <- Keyword.get(context, :call_id),
         activation_id when is_binary(activation_id) or is_nil(activation_id) <-
           Keyword.get(context, :activation_id),
         %ProviderContext{} = provider <- Keyword.get(context, :provider) do
      TextToSpeechAttempt.start(
        request,
        Id.generate(:tts_attempt),
        call_id,
        activation_id,
        provider,
        media_format
      )
    else
      _not_configured -> nil
    end
  end

  @spec observe_event(nil | map(), Event.t(), nil | keyword(), map()) :: nil | map()
  def observe_event(current, %Event{usage: usage}, context, media_format),
    do: observe_snapshot(current, usage, context, media_format)

  @spec observe_audio(nil | map(), Audio.t()) :: nil | map()
  def observe_audio(current, %Audio{usage: %TTSUsage{} = usage}),
    do: apply_snapshot(current, usage)

  def observe_audio(current, %Audio{}), do: current

  @spec finish(nil | map(), :succeeded | :failed | :cancelled, pid()) :: nil | map()
  def finish(nil, outcome, owner)
      when outcome in [:succeeded, :failed, :cancelled] and is_pid(owner),
      do: nil

  def finish(%{usage: %TextToSpeechAttempt{} = usage} = current, outcome, owner)
      when outcome in [:succeeded, :failed, :cancelled] and is_pid(owner) do
    case TextToSpeechAttempt.finish(usage, outcome, DateTime.utc_now(:millisecond)) do
      {:ok, observations} ->
        send(owner, {:vxpipe_usage_observations, self(), observations})

      {:error, :invalid_text_to_speech_usage} ->
        :ok
    end

    %{current | usage: nil}
  end

  def finish(current, outcome, owner)
      when outcome in [:succeeded, :failed, :cancelled] and is_pid(owner),
      do: current

  defp observe_snapshot(current, nil, _context, _media_format), do: current

  defp observe_snapshot(
         %{usage: nil, request: request} = current,
         %TTSUsage{} = usage,
         context,
         media_format
       ) do
    current
    |> Map.put(:usage, start(request, context, media_format))
    |> apply_snapshot(usage)
  end

  defp observe_snapshot(current, %TTSUsage{} = usage, _context, _media_format),
    do: apply_snapshot(current, usage)

  defp apply_snapshot(%{usage: %TextToSpeechAttempt{} = attempt} = current, usage) do
    %{current | usage: TextToSpeechAttempt.observe_semantic(attempt, usage)}
  end

  defp apply_snapshot(current, _usage), do: current
end
