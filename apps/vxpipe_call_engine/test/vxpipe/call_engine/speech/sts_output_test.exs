defmodule Vxpipe.CallEngine.Speech.STSOutputTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSTT
  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: MorseTTS
  alias Vxpipe.CallEngine.Speech.{Channel, Event, Request, Session}
  alias Vxpipe.CallEngine.SpeechProviderContract, as: Contract
  alias Vxpipe.CallEngine.SpeechSessionOwner, as: Owner
  alias Vxpipe.CallEngine.SpeechSTSContractProvider, as: Provider

  test "only the ready STS consumer may authorize and settle output" do
    session =
      Contract.start_session!(Contract.start_scope!(), Provider, private: [observer: self()])

    assert_receive {:vxpipe_speech, %Event{kind: :ready} = ready}
    assert {:error, :not_ready} = Session.admit_output(session, make_ref())
    assert :ok = Session.ack(session, ready)

    stranger = start_supervised!({Owner, self()})

    assert {:error, :not_owner} =
             Owner.run(stranger, fn _ -> Session.admit_output(session, make_ref()) end)

    assert {:ok, output} = Session.admit_output(session, make_ref())
    assert :ok = complete(session, output)
    Contract.ack_event!(session, :output_completed)

    assert {:error, :not_owner} =
             Owner.run(stranger, fn _ -> Session.settle_output(session, output, 0) end)

    assert :ok = Session.settle_output(session, output, 0)

    for provider <- [MorseSTT, MorseTTS] do
      other = Contract.start_profile!(provider)
      assert {:error, :unsupported_operation} = Session.admit_output(other, make_ref())
      assert {:error, :stale_request} = Session.settle_output(other, output, 0)
      assert :ok = Session.close(other)
    end
  end

  test "queued output admission expires without permitting late output or revoking the session" do
    session = start_session(call_timeout: 50)
    channel = GenServer.whereis(Channel.address(session))
    :ok = :sys.suspend(channel)

    try do
      assert {:error, :command_timeout} = Session.admit_output(session, make_ref())
    after
      :ok = :sys.resume(channel)
    end

    _ = :sys.get_state(channel)
    _ = :sys.get_state(Session.provider(session))
    refute_received {:sts_output_permitted, _, _, _, _}
    assert {:ok, _output} = Session.admit_output(session, make_ref())
  end

  test "the provider receives matching playback settlement once, only after consumer acceptance" do
    session = start_session()
    assert {:ok, output} = Session.admit_output(session, make_ref())
    assert :ok = complete(session, output)
    assert {:error, :output_pending} = Session.settle_output(session, output, 0)
    refute_received {:vxpipe_speech_output_settled, _, _, _, _}
    Contract.ack_event!(session, :output_completed)
    assert :ok = Session.settle_output(session, output, 0)
    turn = output.turn_ref
    ref = output.ref
    assert_receive {:vxpipe_speech_output_settled, _channel, ^turn, ^ref, 0}
    assert {:error, :stale_request} = Session.settle_output(session, output, 0)
    refute_received {:vxpipe_speech_output_settled, _, _, _, _}
  end

  test "completion is bound to the output reference and turn, and cannot release replacement output" do
    session = start_session()
    provider = Session.provider(session)
    assert {:ok, output} = Session.admit_output(session, make_ref())
    assert {:error, :stale_request} = complete(session, %{output | turn_ref: make_ref()})
    assert {:error, :stale_request} = complete(session, %{output | ref: make_ref()})
    assert :ok = complete(session, output)
    assert {:error, :stale_request} = complete(session, output)
    assert {:error, :stale_request} = GenServer.call(provider, {:output, output.ref})
    Contract.ack_event!(session, :output_completed)
    assert :ok = Session.settle_output(session, output, 0)
    assert {:ok, replacement} = Session.admit_output(session, output.turn_ref)
    assert {:error, :stale_request} = Session.settle_output(session, output, 0)
    assert {:error, :busy} = Session.admit_output(session, make_ref())
    assert :ok = complete(session, replacement)
    Contract.ack_event!(session, :output_completed)
    assert :ok = Session.settle_output(session, replacement, 0)
  end

  test "a TTS-shaped settlement cannot bypass STS completion acknowledgement and playback bounds" do
    session = start_session()
    assert {:ok, output} = Session.admit_output(session, make_ref())
    assert :ok = complete(session, output)
    {:ok, descriptor} = Session.describe(session)
    request = Request.new(session, output.ref, self(), descriptor, "E")
    assert {:error, :unsupported_operation} = Session.settle_output(session, request, 100)
    assert {:error, :output_pending} = Session.settle_output(session, output, 0)
    Contract.ack_event!(session, :output_completed)
    assert :ok = Session.settle_output(session, output, 0)
  end

  test "provider loss revokes outstanding output without affecting a sibling" do
    scope = Contract.start_scope!()
    session = Contract.start_session!(scope, Provider, private: [observer: self()])
    Contract.ack_ready!(session)
    sibling = Contract.start_session!(scope, Provider, private: [observer: self()])
    Contract.ack_ready!(sibling)
    assert {:ok, output} = Session.admit_output(session, make_ref())
    provider = Session.provider(session)
    assert {:ok, _credit} = GenServer.call(provider, {:output, output.ref})
    audio = Contract.next_audio!(session, output.ref, :binary.copy(<<0, 0>>, 320))
    tree = Session.tree(session)
    monitor = Process.monitor(tree)
    Process.exit(provider, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^tree, _reason}, 1_000
    assert {:error, :closed} = Session.validate_audio(session, audio)
    assert {:error, :closed} = Session.ack_audio(session, audio)
    assert {:error, :closed} = Session.settle_output(session, output, 0)
    assert {:ok, _other_output} = Session.admit_output(sibling, make_ref())
    assert :ok = Session.push_audio(sibling, <<0, 0>>)
  end

  test "ten concurrent STS sessions each settle ten credited output turns" do
    sessions =
      for _ <- 1..10 do
        owner = start_supervised!(Supervisor.child_spec({Owner, self()}, id: make_ref()))
        {owner, Contract.start_scope!(owner)}
      end

    results =
      Task.async_stream(
        sessions,
        fn {owner, scope} ->
          Owner.run(owner, fn _ ->
            session = Contract.start_session!(scope, Provider, private: [observer: self()])
            Contract.ack_ready!(session)

            for _ <- 1..10 do
              assert :ok = Session.push_audio(session, <<0, 0>>)
              assert :ok = Session.push_text(session, "E")
              Contract.ack_event!(session, :input_submitted)
              assert {:ok, output} = Session.admit_output(session, make_ref())

              assert {:ok, _credit} =
                       GenServer.call(Session.provider(session), {:output, output.ref})

              Contract.ack_audio!(session, output.ref, :binary.copy(<<0, 0>>, 320))
              assert :ok = complete(session, output)
              Contract.ack_event!(session, :output_completed)
              assert :ok = Session.settle_output(session, output, 20)
            end

            Session.close(session)
          end)
        end,
        max_concurrency: 10,
        timeout: 10_000
      )

    assert Enum.to_list(results) == List.duplicate({:ok, :ok}, 10)
  end

  defp start_session(options \\ []),
    do: Contract.start_profile!(Provider, Keyword.put(options, :private, observer: self()))

  defp complete(session, output),
    do:
      GenServer.call(
        Session.provider(session),
        {:emit, :output_completed, [turn_ref: output.turn_ref, request_ref: output.ref]}
      )
end
