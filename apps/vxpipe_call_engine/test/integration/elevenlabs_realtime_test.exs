defmodule Vxpipe.CallEngine.Integration.ElevenLabsRealtimeTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.Providers.ElevenLabs.{Realtime, RealtimeSession}

  @moduletag :live_providers
  @moduletag :live_elevenlabs
  @moduletag :capture_log
  @moduletag timeout: 45_000
  @fixture Path.expand("../fixtures/gpt_live/greeting_24k_mono_s16le.pcm", __DIR__)

  test "Mini handles recorded speech with native turn detection and credited output" do
    check_model("eleven_realtime_v1_mini", 2)
  end

  test "Max handles recorded speech with native turn detection and credited output" do
    check_model("eleven_realtime_v1_max", 1)
  end

  defp check_model(model, turns) do
    observer = self()
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:vxpipe, :elevenlabs, :realtime, :failure],
        fn _, _, metadata, pid -> send(pid, {:realtime_failure, metadata.reason}) end,
        observer
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, config} =
      Realtime.new(
        api_key: System.fetch_env!("ELEVENLABS_API_KEY"),
        model: model,
        system_prompt:
          "Reply to every greeting with only the word hello. Keep every reply under five words."
      )

    tree = start_supervised!({CapabilityTree, owner: self()})

    {:ok, session, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: RealtimeSession,
        options: [model: model],
        private: [config: config],
        owner: self()
      )

    on_exit(fn -> Session.close(session) end)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}, 20_000
    assert :ok = Session.ack(session, ready)
    context = make_ref()
    pcm = File.read!(@fixture) <> :binary.copy(<<0, 0>>, 24_000 * 2)
    assert byte_size(pcm) <= 24_000 * 2 * 6

    outputs =
      for _turn <- 1..turns do
        stream(session, context, pcm)

        result =
          await_output(session, context, System.monotonic_time(:millisecond) + 15_000, %{
            bytes: 0,
            output: nil,
            started?: false,
            ended?: false,
            input: nil,
            text: nil
          })

        assert result.started? and result.ended?
        assert is_binary(result.input) and byte_size(result.input) > 0
        assert is_binary(result.text) and byte_size(result.text) > 0
        assert result.bytes > 0
        result.output
      end

    assert length(Enum.uniq(outputs)) == turns
    assert :ok = Session.close(session)
  end

  defp stream(_session, _context, <<>>), do: :ok

  defp stream(session, context, pcm) do
    size = min(byte_size(pcm), 4_800)
    <<chunk::binary-size(size), rest::binary>> = pcm
    result = Session.push_audio(session, chunk, response_context: context)

    if result != :ok do
      receive do
        {:realtime_failure, reason} -> flunk("Realtime input failed: #{reason}")
      after
        0 -> flunk("Realtime input closed without a protocol diagnostic")
      end
    end

    ref = make_ref()
    Process.send_after(self(), {:pace, ref}, div(size, 48))
    assert_receive {:pace, ^ref}, 1_000
    stream(session, context, rest)
  end

  defp await_output(session, context, deadline, state) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:vxpipe_speech, %Event{session: ^session} = event} ->
        assert :ok = Session.ack(session, event)

        state =
          case event.kind do
            :speech_started ->
              %{state | started?: true}

            :turn_ended ->
              %{state | ended?: true}

            :input_transcript ->
              %{state | input: event.text}

            :output_transcript ->
              %{state | text: event.text}

            :response_started ->
              assert event.response_context == context
              assert {:ok, output} = Session.admit_output(session, event.turn_ref)
              %{state | output: output}

            _kind ->
              state
          end

        if event.kind == :output_completed do
          assert :ok = Session.settle_output(session, state.output, 0)
          state
        else
          await_output(session, context, deadline, state)
        end

      {:vxpipe_speech_audio, %Audio{session: ^session, payload: pcm} = audio} ->
        assert :ok = Session.ack_audio(session, audio)
        assert state.bytes + byte_size(pcm) <= 24_000 * 2 * 10
        await_output(session, context, deadline, %{state | bytes: state.bytes + byte_size(pcm)})

      {:vxpipe_speech_closed, ^session, _reason} ->
        flunk("Realtime session closed before completion")
    after
      remaining -> flunk("Realtime native turn/output timed out")
    end
  end
end
