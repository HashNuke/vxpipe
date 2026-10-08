defmodule Vxpipe.CallEngine.Integration.GeminiLiveHostedLongTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Media.PCMResampler
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.Providers.Google.{STS, STSSession}
  alias Vxpipe.Providers.LiveModels

  @moduletag :live_long
  @moduletag timeout: 1_200_000
  @moduletag capture_log: true
  @duration 1_080_000
  @reply_budget 20_000
  @rotation_event [:vxpipe, :providers, :google, :sts, :resumed]

  @tag :live_long_google_gemini_live_hosted
  test "continuous microphone input and replies survive provider rotation beyond fifteen minutes" do
    {session, final} = run(@duration, 420_000)
    assert final.completed >= 50
    assert final.transcripts >= 50
    assert final.frames > 45_000
    assert final.rotations > 0
    assert final.last_reply - final.started >= @duration - 30_000
    assert final.outputs == %{}
    assert :ok = Session.close(session)

    IO.puts(
      "Live Gemini hosted long: #{elapsed(final)}s, " <>
        "#{final.completed} received replies, #{final.frames} microphone frames, " <>
        "#{final.rotations} resumed connections, controlled trigger=#{final.controlled_rotation?}"
    )
  end

  @tag :live_gemini_resumption
  @tag timeout: 45_000
  test "a controlled goAway resumes a real Google conversation without losing context" do
    {session, final} = run(30_000, 0)
    assert final.completed >= 2
    IO.puts("Probe final checkpoint: #{inspect(checkpoint(final.provider))}")
    assert final.rotations == 1
    assert String.downcase(final.memory_text) =~ "violet"
    assert final.outputs == %{}
    assert :ok = Session.close(session)
  end

  defp run(duration, rotation_after) do
    scope = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, config} =
             STS.new(
               api_key: System.fetch_env!("GEMINI_API_KEY"),
               model: LiveModels.speech("google", :sts),
               voice: "Kore",
               system_prompt: "Reply to each greeting briefly in English with Hello."
             )

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(scope),
               provider: STSSession,
               options: [response_start?: true],
               private: [config: config],
               owner: self()
             )

    await_ready(session)
    provider = Session.provider(session)
    assert is_pid(provider)
    handler = {__MODULE__, make_ref()}

    assert :ok =
             :telemetry.attach(handler, @rotation_event, &__MODULE__.rotation/4, %{
               owner: self(),
               provider: provider
             })

    on_exit(fn -> :telemetry.detach(handler) end)
    path = Path.expand("../fixtures/gpt_live/greeting_24k_mono_s16le.pcm", __DIR__)
    {fixture, 0} = PCMResampler.resample(File.read!(path), 0, 24_000, 16_000)
    assert byte_size(fixture) in 2..96_000

    fixture =
      fixture <> :binary.copy(<<0, 0>>, rem(640 - rem(byte_size(fixture), 640), 640) |> div(2))

    started = now_ms()

    state = %{
      started: started,
      duration: duration,
      provider: provider,
      request_rotation_at: if(is_integer(rotation_after), do: started + rotation_after),
      controlled_rotation?: false,
      probe?: rotation_after == 0,
      memory_reply?: false,
      memory_text: "",
      next_report: started + 60_000,
      next_utterance: started,
      awaiting_reply: nil,
      fixture: fixture,
      input: <<>>,
      context: make_ref(),
      outputs: %{},
      bytes: 0,
      frames: 0,
      completed: 0,
      transcripts: 0,
      rotations: 0,
      last_reply: nil
    }

    state =
      if state.probe? do
        assert :ok =
                 Session.push_text(session, "Remember the word violet for later. Say recorded.",
                   response_context: state.context
                 )

        %{state | awaiting_reply: now_ms() + @reply_budget, next_utterance: started + duration}
      else
        state
      end

    send(self(), :microphone_tick)
    {session, exchange(session, state)}
  end

  def rotation(_event, _measurements, %{reason: :go_away}, config) do
    if self() == config.provider, do: send(config.owner, :gemini_rotated)
  end

  def rotation(_event, _measurements, _metadata, _config), do: :ok

  defp await_ready(session) do
    receive do
      {:vxpipe_speech, %Event{session: ^session, kind: :ready} = event} ->
        assert :ok = Session.ack(session, event)

      {:vxpipe_speech_closed, ^session, reason} ->
        flunk("Gemini startup closed: #{inspect(reason)}")
    after
      15_000 -> flunk("Gemini did not acknowledge setup")
    end
  end

  defp exchange(session, state) do
    if now_ms() - state.started >= state.duration and state.awaiting_reply == nil do
      state
    else
      receive do
        :microphone_tick ->
          state = microphone(session, state)
          Process.send_after(self(), :microphone_tick, 20)
          exchange(session, state)

        :gemini_rotated ->
          IO.puts("Live Gemini hosted long: provider rotation at #{elapsed(state)}s")
          state = %{state | rotations: state.rotations + 1}

          state =
            if state.probe? do
              assert :ok =
                       Session.push_text(
                         session,
                         "What word did I ask you to remember? Say only that word.",
                         response_context: state.context
                       )

              %{state | awaiting_reply: now_ms() + @reply_budget, memory_reply?: true}
            else
              state
            end

          exchange(session, state)

        {:vxpipe_speech, %Event{session: ^session} = event} ->
          assert :ok = Session.ack(session, event)
          exchange(session, track(session, event, state))

        {:vxpipe_speech_audio, %Audio{session: ^session} = audio} ->
          assert :ok = Session.validate_audio(session, audio)
          assert byte_size(audio.payload) > 0
          assert :ok = Session.ack_audio(session, audio)
          assert Map.has_key?(state.outputs, audio.request_ref)

          outputs =
            Map.update!(
              state.outputs,
              audio.request_ref,
              &%{&1 | bytes: &1.bytes + byte_size(audio.payload)}
            )

          exchange(session, %{
            state
            | outputs: outputs,
              bytes: state.bytes + byte_size(audio.payload)
          })

        {:vxpipe_speech_closed, ^session, reason} ->
          flunk("Gemini closed at #{elapsed(state)}s: #{inspect(reason)}")
      after
        @reply_budget -> flunk("Gemini microphone/event stream stalled at #{elapsed(state)}s")
      end
    end
  end

  defp microphone(session, state) do
    now = now_ms()
    state = request_rotation(state, now)

    if state.awaiting_reply,
      do: assert(now < state.awaiting_reply, "Gemini reply stalled at #{elapsed(state)}s")

    state =
      if state.input == <<>> and state.awaiting_reply == nil and
           now >= state.next_utterance and now - state.started < state.duration do
        %{
          state
          | input: state.fixture,
            awaiting_reply: now + @reply_budget,
            next_utterance: now + 15_000
        }
      else
        state
      end

    {frame, rest} =
      case state.input do
        <<frame::binary-size(640), rest::binary>> -> {frame, rest}
        <<>> -> {:binary.copy(<<0, 0>>, 320), <<>>}
      end

    assert :ok = Session.push_audio(session, frame, response_context: state.context)
    state = %{state | input: rest, frames: state.frames + 1}

    if now >= state.next_report do
      IO.puts(
        "Live Gemini hosted long: #{elapsed(state)}s, replies=#{state.completed}, rotations=#{state.rotations}"
      )

      %{state | next_report: state.next_report + 60_000}
    else
      state
    end
  end

  defp request_rotation(state, now) do
    if state.rotations == 0 and not state.controlled_rotation? and state.completed > 0 and
         state.awaiting_reply == nil and is_integer(state.request_rotation_at) and
         now >= state.request_rotation_at do
      provider_state = :sys.get_state(state.provider)
      snapshot = checkpoint(state.provider)

      IO.puts(
        "Live Gemini hosted long: controlled goAway at #{elapsed(state)}s; #{inspect(snapshot)}"
      )

      # The short probe controls only the lifecycle notification. The handle,
      # replacement socket and continued conversation are real Google resources.
      # The long lane controls this boundary if Google has not already rotated.
      # Only the notification is injected: resumption and model context are real.
      payload = JSON.encode!(%{"goAway" => %{"timeLeft" => "60s"}})
      send(state.provider, {:vxpipe_sts_transport, provider_state.wire, {:message, payload}})
      %{state | controlled_rotation?: true}
    else
      state
    end
  end

  defp checkpoint(provider) do
    state = :sys.get_state(provider)

    state
    |> Map.take([
      :renew_requested?,
      :resuming?,
      :resumption_ambiguous?,
      :awaiting_model_activity?,
      :awaiting_audio_final?,
      :model_turn_complete?,
      :interaction_status
    ])
    |> Map.put(:handle?, is_binary(state.resumption_handle))
    |> Map.put(:caller?, state.caller != nil)
  end

  defp track(session, %Event{kind: :response_started, turn_ref: turn}, state) do
    assert {:ok, handle} = Session.admit_output(session, turn)
    %{state | outputs: Map.put(state.outputs, handle.ref, %{handle: handle, bytes: 0})}
  end

  defp track(session, %Event{kind: :output_completed, request_ref: reference}, state) do
    {output, outputs} = Map.pop(state.outputs, reference)
    assert output != nil and output.bytes > 0
    # Direct consumption acknowledges PCM receipt, not remote carrier playout.
    assert :ok = Session.settle_output(session, output.handle, 0)

    %{
      state
      | outputs: outputs,
        completed: state.completed + 1,
        awaiting_reply: nil,
        last_reply: now_ms()
    }
  end

  defp track(
         _session,
         %Event{kind: :output_transcript, text: text},
         %{memory_reply?: true} = state
       ),
       do: %{state | memory_text: state.memory_text <> text}

  defp track(_session, %Event{kind: :input_transcript, final: true, text: text}, state)
       when text != "",
       do: %{state | transcripts: state.transcripts + 1}

  defp track(_session, %Event{kind: :failed}, state),
    do: flunk("Gemini provider failed at #{elapsed(state)}s")

  defp track(_session, _event, state), do: state
  defp elapsed(state), do: div(now_ms() - state.started, 1_000)
  defp now_ms, do: System.monotonic_time(:millisecond)
end
