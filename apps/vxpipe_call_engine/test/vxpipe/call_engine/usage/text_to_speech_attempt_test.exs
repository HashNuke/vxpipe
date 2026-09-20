defmodule Vxpipe.CallEngine.Usage.TextToSpeechAttemptTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.TTSUsage
  alias Vxpipe.CallEngine.TextToSpeechRequest
  alias Vxpipe.CallEngine.Usage.{ProviderContext, TextToSpeechAttempt}

  @observed_at ~U[2026-09-12 00:15:00.123Z]

  test "projects accepted text and generated PCM duration with genuine provider identifiers" do
    attempt =
      request("Hello 👋")
      |> TextToSpeechAttempt.start(
        "tts-attempt-1",
        "call-usage",
        "activation-agent",
        provider_context(),
        media_format()
      )
      |> TextToSpeechAttempt.observe_semantic(usage(32_000, "provider-request-1"))

    assert {:ok, observations} =
             TextToSpeechAttempt.finish(attempt, :succeeded, @observed_at)

    assert [audio, text] = Enum.sort_by(observations, & &1.measurement.component)

    assert audio.measurement.component == "generated_audio_duration"
    assert audio.measurement.unit == :milliseconds
    assert audio.measurement.quantity == 1_000
    assert audio.measurement.provenance == :locally_measured

    assert text.measurement.component == "input_characters"
    assert text.measurement.unit == :characters
    assert text.measurement.quantity == 7
    assert text.measurement.provenance == :locally_measured

    assert Enum.all?(observations, fn observation ->
             observation.capability == :text_to_speech and
               observation.outcome == :succeeded and
               observation.attempt_id == "tts-attempt-1" and
               observation.call_id == "call-usage" and
               observation.tenant_id == "tenant-usage" and
               observation.provider.request_id == "provider-request-1" and
               observation.provider.operation_id == nil and
               observation.attribution.participant_id == "participant-agent" and
               observation.attribution.activation_id == "activation-agent" and
               observation.attribution.turn_id == "turn-usage"
           end)

    assert observations |> Enum.map(& &1.id) |> Enum.uniq() |> length() == 2
    refute inspect(attempt) =~ "Hello"
  end

  test "retains failed accepted input without inventing an audio-duration measurement" do
    attempt =
      request("accepted input")
      |> TextToSpeechAttempt.start(
        "tts-attempt-2",
        "call-usage",
        "activation-agent",
        provider_context(),
        media_format()
      )
      |> TextToSpeechAttempt.observe_semantic(usage(0, "provider-request-2"))

    assert {:ok, [observation]} = TextToSpeechAttempt.finish(attempt, :failed, @observed_at)

    assert observation.outcome == :failed
    assert observation.provider.request_id == "provider-request-2"
    assert observation.provider.operation_id == nil
    assert observation.measurement.component == "input_characters"
    assert observation.measurement.quantity == 14
  end

  test "marks interrupted generated audio as cancelled without using playout duration" do
    attempt =
      request("interrupted")
      |> TextToSpeechAttempt.start(
        "tts-attempt-3",
        "call-usage",
        "activation-agent",
        provider_context(),
        media_format()
      )
      |> TextToSpeechAttempt.observe_semantic(usage(16_000, "provider-request-3"))

    assert {:ok, observations} = TextToSpeechAttempt.finish(attempt, :cancelled, @observed_at)

    assert Enum.all?(observations, &(&1.outcome == :cancelled))

    audio = Enum.find(observations, &(&1.measurement.component == "generated_audio_duration"))
    assert audio.measurement.quantity == 500
  end

  defp request(text) do
    %TextToSpeechRequest{
      tenant_id: "tenant-usage",
      room_id: "room-usage",
      incarnation_id: "incarnation-usage",
      participant_id: "participant-agent",
      source_participant_id: "participant-caller",
      connection_id: "connection-caller",
      command_id: "command-usage",
      correlation_id: "turn-usage",
      output_id: "output-usage",
      text: text,
      output_sink: self()
    }
  end

  defp provider_context do
    assert {:ok, provider} =
             ProviderContext.new(
               name: "deepgram",
               integration_id: "primary-voice",
               model: "flux-test"
             )

    provider
  end

  defp media_format do
    %{codec: :linear16, sample_rate: 16_000, channels: 1, byte_order: :little}
  end

  defp usage(generated_bytes, provider_request_id) do
    %TTSUsage{
      session: :session,
      request_ref: make_ref(),
      input_characters: 1,
      usage_identity: %{},
      provider_request_id: provider_request_id,
      provenance: :provider_reported,
      generated_bytes: generated_bytes,
      generation: :generating
    }
  end
end
