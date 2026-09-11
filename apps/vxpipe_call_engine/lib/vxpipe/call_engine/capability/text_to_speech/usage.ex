defmodule Vxpipe.CallEngine.Capability.TextToSpeech.Usage do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.TextToSpeech.Signal
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

  @spec observe_signal(nil | map(), Signal.t()) :: nil | map()
  def observe_signal(nil, %Signal{}), do: nil

  def observe_signal(%{usage: %TextToSpeechAttempt{} = usage} = current, %Signal{} = signal) do
    %{current | usage: TextToSpeechAttempt.observe_signal(usage, signal)}
  end

  def observe_signal(current, %Signal{}), do: current

  @spec observe_audio(nil | map(), binary()) :: nil | map()
  def observe_audio(nil, audio) when is_binary(audio), do: nil

  def observe_audio(%{usage: %TextToSpeechAttempt{} = usage} = current, audio)
      when is_binary(audio) do
    %{current | usage: TextToSpeechAttempt.observe_audio(usage, audio)}
  end

  def observe_audio(current, audio) when is_binary(audio), do: current

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
end
