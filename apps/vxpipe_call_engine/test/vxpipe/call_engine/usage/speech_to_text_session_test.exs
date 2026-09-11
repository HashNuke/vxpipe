defmodule Vxpipe.CallEngine.Usage.SpeechToTextSessionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.Usage.{ProviderContext, SpeechToTextSession}

  @observed_at ~U[2026-09-12 01:30:00.123Z]

  test "counts only a final turn and retains provider audio duration and identifiers" do
    session = session()

    {session, []} =
      SpeechToTextSession.observe_signal(
        session,
        signal(:connected, 0, request_id: "provider-request-1"),
        true,
        @observed_at
      )

    {session, [started]} =
      SpeechToTextSession.observe_signal(
        session,
        signal(:transcript_updated, 1,
          provider_turn_index: 7,
          text: "Hello",
          audio_duration_ms: 900
        ),
        true,
        @observed_at
      )

    assert started.outcome == :in_progress
    assert started.measurement == nil
    assert started.source_sequence == 0
    assert started.attribution.service_interval_id == "service-interval-1"

    {session, observations} =
      SpeechToTextSession.observe_signal(
        session,
        signal(:turn_ended, 2,
          provider_turn_index: 7,
          text: "Hello 👋",
          audio_duration_ms: 1_250
        ),
        true,
        @observed_at
      )

    assert [audio, text] = Enum.sort_by(observations, & &1.measurement.component)

    assert audio.measurement.component == "recognized_audio_duration"
    assert audio.measurement.unit == :milliseconds
    assert audio.measurement.quantity == 1_250
    assert audio.measurement.mode == :delta
    assert audio.measurement.status == :final
    assert audio.measurement.provenance == :provider_reported

    assert text.measurement.component == "recognized_text_characters"
    assert text.measurement.unit == :characters
    assert text.measurement.quantity == 7
    assert text.measurement.mode == :delta
    assert text.measurement.status == :final
    assert text.measurement.provenance == :locally_measured

    assert Enum.all?(observations, fn observation ->
             observation.capability == :speech_to_text and
               observation.outcome == :succeeded and
               observation.attempt_id == "stt-attempt-1" and
               observation.call_id == "call-usage" and
               observation.tenant_id == "tenant-usage" and
               observation.provider.request_id == "provider-request-1" and
               observation.source_sequence == 2 and
               observation.attribution.participant_id == "participant-caller" and
               observation.attribution.activation_id == nil and
               observation.attribution.service_interval_id == "service-interval-1"
           end)

    {session, repeated} =
      SpeechToTextSession.observe_signal(
        session,
        signal(:turn_ended, 3,
          provider_turn_index: 7,
          text: "Hello again",
          audio_duration_ms: 2_000
        ),
        true,
        @observed_at
      )

    assert repeated == []
    refute inspect(session) =~ "Hello"
  end

  test "does not retain a character count when transcript storage is denied" do
    {session, observations} =
      session()
      |> SpeechToTextSession.observe_signal(
        signal(:turn_ended, 1,
          request_id: "provider-request-2",
          provider_turn_index: 0,
          text: "private words",
          audio_duration_ms: 640
        ),
        false,
        @observed_at
      )

    assert [started, observation] = observations
    assert started.outcome == :in_progress
    assert started.measurement == nil
    assert observation.measurement.component == "recognized_audio_duration"
    assert observation.measurement.quantity == 640
    refute inspect(session) =~ "private words"
  end

  test "retains a proven failed provider session once without inventing measurements" do
    {session, []} =
      SpeechToTextSession.observe_signal(
        session(),
        signal(:connected, 0, request_id: "provider-request-failed"),
        true,
        @observed_at
      )

    {session, [started, observation]} =
      SpeechToTextSession.finish(session, :failed, @observed_at)

    assert started.outcome == :in_progress
    assert started.measurement == nil
    assert started.observed_at == @observed_at
    assert started.source_sequence == 0
    assert observation.outcome == :failed
    assert observation.measurement == nil
    assert observation.source_sequence == nil
    assert observation.provider.request_id == "provider-request-failed"
    assert observation.attribution.service_interval_id == "service-interval-1"

    assert {^session, []} = SpeechToTextSession.finish(session, :failed, @observed_at)

    assert {_session, []} =
             session()
             |> SpeechToTextSession.finish(:failed, @observed_at)
  end

  defp session do
    SpeechToTextSession.start(
      %{
        tenant_id: "tenant-usage",
        room_id: "room-usage",
        incarnation_id: "incarnation-usage",
        participant_id: "participant-caller"
      },
      "stt-attempt-1",
      "service-interval-1",
      "call-usage",
      nil,
      provider_context()
    )
  end

  defp provider_context do
    assert {:ok, provider} =
             ProviderContext.new(
               name: "deepgram",
               integration_id: "primary-stt",
               model: "flux-general-en"
             )

    provider
  end

  defp signal(kind, sequence, options) do
    struct!(Signal, [kind: kind, provider_sequence: sequence] ++ options)
  end
end
