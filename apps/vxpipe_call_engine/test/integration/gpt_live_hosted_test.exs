defmodule Vxpipe.CallEngine.Integration.GPTLiveHostedTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.TestGPTLiveHostedTransport
  alias Vxpipe.Providers.OpenAI.{GPTLive, GPTLiveSession}

  @moduletag :live_providers
  @moduletag :live_openai
  @moduletag timeout: 120_000
  @moduletag capture_log: true

  @moduledoc """
  Opt-in hosted GPT-Live acceptance harness.

  This direct-session harness simulates the room yield by calling
  `GPTLiveSession.interrupt/2`; an admitted burst marks its segment yielded
  and eventually emits `:output_completed` without emitting `:interrupted`.
  Real service/carrier interruption remains pending and requires the manual
  phone pass.
  """

  @fixture_bytes_limit 144_000

  test "short turn, talk-over yield, mute hold and forced history reseed" do
    deadline = deadline()
    {session, provider, wire, outputs} = start_ready_session([], deadline)

    assert :ok = Session.set_input_hold(session, true)
    assert {:error, :busy} = Session.push_audio(session, <<0, 0>>, response_context: make_ref())
    assert :ok = Session.set_input_hold(session, false)

    submit_fixture(session, :greeting)

    {%Event{turn_ref: first_turn}, outputs} =
      await_kind(session, :response_started, deadline, outputs)

    {_first_audio, outputs} = await_audio(session, deadline, outputs)

    submit_fixture(session, :interrupt)
    assert :ok = GPTLiveSession.interrupt(provider, first_turn)
    {_yielded_completed, outputs} = await_output_completed(session, first_turn, deadline, outputs)

    {%Event{turn_ref: second_turn}, outputs} =
      await_kind(session, :response_started, deadline, outputs)

    {_second_audio, outputs} = await_audio(session, deadline, outputs)
    {_second_completed, outputs} = await_output_completed(session, second_turn, deadline, outputs)
    assert_settled(outputs)

    assert :ok = Session.append_history(session, {:caller, "Please remember violet."})
    assert :ok = Session.append_history(session, {:agent, "I will remember violet."})

    :ok = GenServer.stop(wire)
    replacement = await_reseeded_wire(wire, deadline)
    assert replacement != wire
    wait_provider_wire(provider, replacement, deadline)

    state = :sys.get_state(provider)
    assert state.ready?
    assert state.reseed_attempted?
    assert state.wire == replacement

    submit_fixture(session, :greeting)
    {_resumed, outputs} = await_kind(session, :response_started, deadline, outputs)
    {_resumed_audio, outputs} = await_audio(session, deadline, outputs)
    {_resumed_completed, outputs} = await_completion(session, deadline, outputs)
    assert_settled(outputs)
  end

  test "delegated function result continues into spoken output" do
    deadline = deadline()

    tools = [
      %{
        "name" => "ping",
        "description" => "Return the short test status when the caller asks to ping.",
        "parametersJsonSchema" => %{"type" => "object", "properties" => %{}}
      }
    ]

    {session, provider, _wire, outputs} =
      start_ready_session(
        [
          tools: tools,
          system_prompt: "When the caller asks to ping, call the ping function before answering."
        ],
        deadline
      )

    submit_fixture(session, :ping)

    {%Event{tool_name: "ping", call_ref: call_ref}, outputs} =
      await_kind(session, :tool_call, deadline, outputs)

    assert :ok = GPTLiveSession.send_tool_result(provider, call_ref, %{"status" => "ready"})
    {_spoken_result, outputs} = await_audio(session, deadline, outputs)
    {_spoken_completed, outputs} = await_completion(session, deadline, outputs)
    assert_settled(outputs)
  end

  defp start_ready_session(options, deadline) do
    scope = start_supervised!({CapabilityTree, owner: self()})
    api_key = System.fetch_env!("OPENAI_API_KEY")

    config_options =
      [api_key: api_key, backend_model: "gpt-5"] ++
        Keyword.take(options, [:tools, :system_prompt])

    {:ok, config} = GPTLive.new(config_options)

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(scope),
               provider: GPTLiveSession,
               options: [backend_model: "gpt-5"],
               private: [
                 config: config,
                 wire_module: TestGPTLiveHostedTransport,
                 wire_options: [observer: self()]
               ],
               owner: self(),
               start_timeout: 20_000
             )

    {_ready, outputs} = await_kind(session, :ready, deadline, %{})
    provider = Session.provider(session)
    wire = :sys.get_state(provider).wire
    await_hosted_event(wire, "session.started", deadline)
    wait_provider_wire(provider, wire, deadline)
    report_idle_audio(wire)
    {session, provider, wire, outputs}
  end

  defp submit_fixture(session, name) do
    path =
      Path.expand(
        "../fixtures/gpt_live/#{fixture_name(name)}_24k_mono_s16le.pcm",
        __DIR__
      )

    pcm = File.read!(path)
    assert byte_size(pcm) in 1..@fixture_bytes_limit
    assert rem(byte_size(pcm), 2) == 0
    context = make_ref()
    chunk_bytes = 48_000

    for offset <- 0..div(byte_size(pcm) - 1, chunk_bytes) do
      size = min(chunk_bytes, byte_size(pcm) - offset * chunk_bytes)
      chunk = binary_part(pcm, offset * chunk_bytes, size)

      unless Session.push_audio(session, chunk, response_context: context) == :ok,
        do: flunk("hosted audio submission failed")
    end
  end

  defp fixture_name(:greeting), do: "greeting"
  defp fixture_name(:interrupt), do: "interrupt"
  defp fixture_name(:ping), do: "ping"

  defp await_kind(session, kind, deadline, outputs) do
    await_session(session, deadline, outputs, fn
      %Event{kind: ^kind} -> true
      _other -> false
    end)
  end

  defp await_audio(session, deadline, outputs),
    do: await_session(session, deadline, outputs, &match?(%Audio{}, &1))

  defp await_output_completed(session, turn_ref, deadline, outputs) do
    await_session(session, deadline, outputs, fn
      %Event{kind: :output_completed, turn_ref: ^turn_ref} -> true
      _other -> false
    end)
  end

  defp await_completion(session, deadline, outputs) do
    await_session(session, deadline, outputs, fn
      %Event{kind: :output_completed} -> true
      _other -> false
    end)
  end

  defp assert_settled(outputs) do
    assert outputs == %{}, "hosted output still pending; settle completed output before exit"
  end

  defp await_session(session, deadline, outputs, selected?) do
    timeout = remaining(deadline)

    receive do
      {:vxpipe_speech, %Event{session: ^session} = event} ->
        assert :ok = Session.ack(session, event)
        outputs = track_event(session, event, outputs)

        if event.kind == :failed, do: flunk("hosted speech session failed")

        if selected?.(event),
          do: {event, outputs},
          else: await_session(session, deadline, outputs, selected?)

      {:vxpipe_speech_audio, %Audio{session: ^session} = audio} ->
        assert :ok = Session.validate_audio(session, audio)
        assert :ok = Session.ack_audio(session, audio)

        if selected?.(audio),
          do: {audio, outputs},
          else: await_session(session, deadline, outputs, selected?)

      {:vxpipe_speech_closed, ^session, _reason} ->
        flunk("hosted speech session closed before acceptance")
    after
      timeout -> flunk("hosted speech event timed out")
    end
  end

  defp track_event(session, %Event{kind: :response_started, turn_ref: turn_ref} = _event, outputs)
       when is_reference(turn_ref) do
    assert {:ok, output} = Session.admit_output(session, turn_ref)
    Map.put(outputs, turn_ref, output)
  end

  defp track_event(
         session,
         %Event{kind: :output_completed, turn_ref: turn_ref} = _event,
         outputs
       )
       when is_reference(turn_ref) do
    case Map.pop(outputs, turn_ref) do
      {nil, _outputs} ->
        outputs

      {handle, rest} ->
        assert :ok = Session.settle_output(session, handle, 0)
        rest
    end
  end

  defp track_event(_session, _event, outputs), do: outputs

  defp await_hosted_event(wire, type, deadline) do
    receive do
      {:gpt_live_hosted_event, ^wire, ^type} -> :ok
    after
      remaining(deadline) -> flunk("hosted socket event timed out")
    end
  end

  defp await_reseeded_wire(old_wire, deadline) do
    receive do
      {:gpt_live_hosted_event, wire, "session.started"} when wire != old_wire -> wire
    after
      remaining(deadline) -> flunk("hosted reseed did not start a replacement session")
    end
  end

  defp wait_provider_wire(provider, wire, deadline) do
    state = :sys.get_state(provider)

    cond do
      state.ready? and state.wire == wire ->
        :ok

      remaining(deadline) == 0 ->
        flunk("hosted provider did not acknowledge the new session before deadline")

      true ->
        receive after: (25 -> :ok)
        wait_provider_wire(provider, wire, deadline)
    end
  end

  defp report_idle_audio(wire) do
    observed? =
      receive do
        {:gpt_live_hosted_event, ^wire, "session.output_audio.delta"} -> true
      after
        1_000 -> false
      end

    IO.puts("hosted idle output_audio.delta observed: #{observed?}")
    observed?
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 110_000
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
