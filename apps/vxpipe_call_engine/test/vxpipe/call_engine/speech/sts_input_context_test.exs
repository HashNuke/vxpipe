defmodule Vxpipe.CallEngine.Speech.STSInputContextTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log
  alias Vxpipe.CallEngine.Speech.{
    CapabilityTree,
    Channel,
    Descriptor,
    Input,
    ResponseContexts,
    Session
  }

  alias Vxpipe.CallEngine.{SpeechContextProbe, SpeechSessionOwner}

  test "atomic ordered operations stage before callback and accept only afterwards" do
    session = session()
    context = make_ref()
    assert :ok = Session.push_audio(session, <<0, 0>>, response_context: context)
    assert_receive {:context_input, ^context, {:audio, <<0, 0>>}, staged}
    assert ResponseContexts.status(staged, context) == :staged
    assert status(session, context) == :accepted
    assert :ok = Session.push_text(session, "hello", response_context: context)
    assert_receive {:context_input, ^context, {:text, ref, "hello"}, accepted}
    assert is_reference(ref)
    assert ResponseContexts.status(accepted, context) == :accepted
    assert_receive {:early_semantics, :ok}
    assert :ok = Session.input_activity(session, :ended, response_context: context)
    assert_receive {:context_input, ^context, {:activity, :ended}, _}
    refute_received {:legacy_input, _}
  end

  test "closed options reject invalid duplicate and unknown keys without delivery" do
    session = session()

    for options <- [
          [response_context: nil],
          [response_context: "not-ref"],
          [unknown: make_ref()],
          [response_context: make_ref(), unknown: true],
          [response_context: make_ref(), response_context: make_ref()],
          %{},
          [:bad]
        ] do
      assert {:error, :invalid_options} = Session.push_audio(session, <<0, 0>>, options)
      assert {:error, :invalid_options} = Session.push_text(session, "hello", options)
      assert {:error, :invalid_options} = Session.input_activity(session, :ended, options)
    end

    assert {:error, :invalid_response_context} = Session.push_audio(session, <<0, 0>>)
    assert {:error, :invalid_response_context} = Session.push_text(session, "hello")
    assert {:error, :invalid_response_context} = Session.input_activity(session, :ended)
    refute_received {:context_input, _, _, _}
    refute_received {:legacy_input, _}
  end

  test "legacy dispatch is unchanged and context cannot be silently discarded" do
    session = session(options: [response_start?: false, turn_control: "hybrid"])
    assert :ok = Session.push_audio(session, <<0, 0>>)
    assert_receive {:legacy_input, {:audio, <<0, 0>>}}
    assert :ok = Session.push_text(session, "hello", [])
    assert_receive {:legacy_input, {:text, _, "hello"}}
    assert :ok = Session.input_activity(session, :ended)
    assert_receive {:legacy_input, {:activity, :ended}}

    assert {:error, :unsupported_operation} =
             Session.push_audio(session, <<0, 0>>, response_context: make_ref())

    refute_received {:context_input, _, _, _}
  end

  test "failed first use rolls back even with early semantics; failed reuse preserves acceptance" do
    session = session()
    provider = Session.provider(session)
    context = make_ref()
    :ok = GenServer.call(provider, {:configure_result, {:error, :busy}, false})
    assert {:error, :busy} = Session.push_text(session, "hello", response_context: context)
    assert_receive {:context_input, ^context, {:text, _, _}, staged}
    assert ResponseContexts.status(staged, context) == :staged
    assert_receive {:early_semantics, :ok}
    assert status(session, context) == :unknown
    :ok = GenServer.call(provider, {:configure_result, :ok, false})
    assert :ok = Session.push_audio(session, <<0, 0>>, response_context: context)
    :ok = GenServer.call(provider, {:configure_result, {:error, :unsupported_operation}, false})

    assert {:error, :unsupported_operation} =
             Session.push_audio(session, <<0, 0>>, response_context: context)

    assert status(session, context) == :accepted
  end

  test "16 retained contexts allow reuse but reject a seventeenth without dispatch" do
    session = session()
    contexts = Enum.map(1..16, fn _ -> make_ref() end)

    for context <- contexts do
      assert :ok = Session.push_audio(session, <<0, 0>>, response_context: context)
      assert_receive {:context_input, ^context, _, _}
    end

    rejected = make_ref()
    assert {:error, :busy} = Session.push_audio(session, <<0, 0>>, response_context: rejected)
    assert status(session, rejected) == :unknown
    refute_received {:context_input, ^rejected, _, _}
    assert :ok = Session.push_audio(session, <<0, 0>>, response_context: hd(contexts))
  end

  test "wrong consumer and not-ready or prepared allocation cannot stage contexts" do
    session = session(ready?: false)
    context = make_ref()
    assert {:error, :not_ready} = Session.push_audio(session, <<0, 0>>, response_context: context)
    assert status(session, context) == :unknown
    stranger = start_supervised!({SpeechSessionOwner, self()})

    assert {:error, :not_owner} =
             SpeechSessionOwner.run(stranger, fn _ ->
               Session.push_audio(session, <<0, 0>>, response_context: context)
             end)

    prepared = session(consumer: nil, lease: self(), ready?: false)
    assert {:error, :not_owner} = Session.push_text(prepared, "hello", response_context: context)
    assert status(prepared, context) == :unknown
    refute_received {:context_input, _, _, _}
  end

  test "held callback occupies the same bounded slot and remains staged until accepted" do
    session = session()
    provider = Session.provider(session)
    context = make_ref()
    :ok = GenServer.call(provider, {:configure_result, :ok, true})
    request = submit_async(session, context)
    assert_receive {:context_input, ^context, _, _}
    assert status(session, context) == :staged
    assert {:error, :busy} = Session.push_text(session, "next", response_context: make_ref())
    :ok = GenServer.call(provider, :release)
    assert {:reply, :ok} = :gen.wait_response(request, 1_000)
    assert status(session, context) == :accepted
  end

  test "timeout after claim never accepts input and tears down the allocation" do
    session = session(call_timeout: 100)
    provider = Session.provider(session)
    context = make_ref()
    :ok = GenServer.call(provider, {:configure_result, :ok, true})
    channel = GenServer.whereis(Channel.address(session))
    monitor = Process.monitor(channel)
    request = submit_async(session, context, 100)
    assert_receive {:context_input, ^context, _, snapshot}
    assert ResponseContexts.status(snapshot, context) == :staged
    assert {:reply, {:error, :session_failed}} = :gen.wait_response(request, 1_000)
    assert_receive {:DOWN, ^monitor, :process, ^channel, _}, 1_000
  end

  test "queued expired input is not staged or dispatched after resume" do
    session = session(call_timeout: 50)
    channel = GenServer.whereis(Channel.address(session))
    context = make_ref()
    :ok = :sys.suspend(channel)

    try do
      assert {:error, :command_timeout} =
               Session.push_audio(session, <<0, 0>>, response_context: context)
    after
      :ok = :sys.resume(channel)
    end

    assert status(session, context) == :unknown
    _ = :sys.get_state(Input.address(session))
    refute_received {:context_input, _, _, _}
  end

  test "descriptor opt-in is boolean and STS-only" do
    {:ok, descriptor} = SpeechContextProbe.configure(turn_control: "hybrid")
    assert :ok = Descriptor.validate(descriptor)

    assert {:error, :invalid_descriptor} =
             Descriptor.validate(Map.put(descriptor, :response_start?, :yes))

    {:ok, stt} = Vxpipe.CallEngine.Provider.MorseCodeSTT.Session.configure([])

    assert {:error, :invalid_descriptor} =
             Descriptor.validate(Map.put(stt, :response_start?, true))
  end

  test "opted-in provider without atomic callback rejects rather than falling back" do
    session = session(provider: Vxpipe.CallEngine.SpeechContextUnsupportedProbe)
    context = make_ref()

    assert {:error, :unsupported_operation} =
             Session.push_audio(session, <<0, 0>>, response_context: context)

    assert {:error, :unsupported_operation} =
             Session.push_text(session, "hello", response_context: context)

    assert {:error, :unsupported_operation} =
             Session.input_activity(session, :ended, response_context: context)

    assert status(session, context) == :unknown
    refute_received {:legacy_input, _}
    refute_received {:context_input, _, _, _}
  end

  test "provider cannot issue a context through the consumer input boundary" do
    session = session()
    context = make_ref()

    assert {:error, :not_owner} =
             GenServer.call(Session.provider(session), {:provider_context_attempt, context})

    assert status(session, context) == :unknown
    refute_received {:context_input, _, _, _}
  end

  test "expiry before worker claim tears down staged input without delivering it" do
    session = session(call_timeout: 100)
    input = GenServer.whereis(Input.address(session))
    channel = GenServer.whereis(Channel.address(session))
    monitor = Process.monitor(channel)
    :ok = :sys.suspend(input)
    context = make_ref()
    request = submit_async(session, context, 100)
    assert status(session, context) == :staged
    assert {:reply, {:error, :session_failed}} = :gen.wait_response(request, 1_000)
    assert_receive {:DOWN, ^monitor, :process, ^channel, _}, 1_000
    refute_received {:context_input, _, _, _}
  end

  defp session(options \\ []) do
    {ready?, options} = Keyword.pop(options, :ready?, true)

    tree =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))

    hold_ready? = not ready? and Keyword.get(options, :consumer, self()) != nil

    defaults = [
      provider: SpeechContextProbe,
      private: [observer: self(), hold_ready?: hold_ready?],
      options: [turn_control: "hybrid"]
    ]

    {:ok, session, :starting} =
      Session.start(CapabilityTree.scope(tree), Keyword.merge(defaults, options))

    channel = Channel.address(session)
    assert_receive {:context_probe_bound, ^channel}, 1_000

    cond do
      Keyword.get(options, :consumer, self()) == nil ->
        assert_receive {:vxpipe_speech_prepared, ^session, _}, 1_000

      ready? ->
        assert_receive {:vxpipe_speech, %{session: ^session} = ready}, 1_000
        assert :ok = Session.ack(session, ready)

      true ->
        :ok
    end

    session
  end

  defp status(session, context),
    do:
      ResponseContexts.status(:sys.get_state(Channel.address(session)).response_contexts, context)

  defp submit_async(session, context, timeout \\ 1_000) do
    command = %{
      ref: make_ref(),
      token: :atomics.new(1, []),
      response_context: context,
      deadline: System.monotonic_time(:millisecond) + timeout
    }

    :gen.send_request(
      Channel.address(session),
      :"$gen_call",
      {:input, session, command, <<0, 0>>}
    )
  end
end
