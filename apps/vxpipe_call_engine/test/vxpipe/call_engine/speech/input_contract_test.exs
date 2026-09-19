defmodule Vxpipe.CallEngine.Speech.InputContractTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Input, Session}
  alias Vxpipe.CallEngine.Usage.{ProviderContext, SpeechToTextSession}
  alias Vxpipe.CallEngine.{SpeechDeferredSTT, SpeechSessionOwner, SpeechSessionProbe}

  @observed_at ~U[2026-09-19 12:00:00Z]

  test "provider acceptance precedes processing and a full input slot rejects without closing" do
    {allocation, provider} = deferred_session()
    assert :ok = Session.push_audio(allocation, <<0, 0>>)
    refute_received {:vxpipe_speech, _event}

    assert {:error, :busy} = Session.push_audio(allocation, <<1, 0>>)
    assert 2 = GenServer.call(provider, :complete_input)
    assert :ok = Session.push_audio(allocation, <<2, 0>>)
    assert :ok = Session.close(allocation)
  end

  test "accepted audio starts usage once even if deferred processing later fails" do
    {allocation, provider} = deferred_session()
    {usage, [started]} = accept(usage(), Session.push_audio(allocation, <<0, 0>>))
    assert started.outcome == :in_progress
    assert started.measurement == nil
    refute_received {:vxpipe_speech, _event}

    assert {^usage, []} = accept(usage, Session.push_audio(allocation, <<1, 0>>))
    assert 2 = GenServer.call(provider, :complete_input)
    {usage, []} = accept(usage, Session.push_audio(allocation, <<2, 0>>))

    monitor = Process.monitor(provider)
    assert :ok = GenServer.call(provider, :fail_input)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}, 500
    assert_receive {:vxpipe_speech_closed, ^allocation, :session_failed}, 500

    {usage, [failed]} = SpeechToTextSession.finish(usage, :failed, @observed_at)
    assert failed.outcome == :failed
    assert failed.measurement == nil
    assert {^usage, []} = SpeechToTextSession.finish(usage, :failed, @observed_at)
  end

  test "input rejected before provider acceptance creates no usage evidence" do
    {allocation, _provider} = deferred_session()
    usage = usage()
    assert {^usage, []} = accept(usage, Session.push_audio(allocation, <<>>))
    assert :ok = Session.close(allocation)
    assert {_usage, []} = SpeechToTextSession.finish(usage, :cancelled, @observed_at)
  end

  test "duplicate dispatch and late completion cannot release a newer input slot" do
    owner = start_supervised!({SpeechSessionOwner, self()})
    tree = start_supervised!({CapabilityTree, owner: self()})
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: SpeechSessionProbe,
        owner: owner,
        private: [observer: self(), hold_input?: true, input_result: :ok]
      )

    assert_receive {:probe_initializing, provider, channel}, 500
    channel = GenServer.whereis(channel)
    assert_receive {:speech_owner, ^owner, {:vxpipe_speech, ready}}, 500
    :ok = SpeechSessionOwner.run(owner, fn _ -> Session.ack(allocation, ready) end)
    input = GenServer.whereis(Input.address(allocation))
    observer = self()

    push = fn id ->
      Task.Supervisor.async_nolink(tasks, fn ->
        result =
          SpeechSessionOwner.run(owner, fn _ -> Session.push_audio(allocation, <<0, 0>>) end)

        send(observer, {:input_finished, id, result})
      end)
    end

    first = push.(:first)
    assert_receive {:probe_input, ^provider}, 500
    old_command = :sys.get_state(channel).input.command
    Input.submit(allocation, old_command, <<1, 0>>)
    send(provider, :release_input)
    assert_receive {:input_finished, :first, :ok}, 500
    Task.await(first)
    _ = :sys.get_state(input)

    second = push.(:second)
    assert_receive {:probe_input, ^provider}, 500
    new_command = :sys.get_state(channel).input.command
    refute old_command.ref == new_command.ref
    GenServer.cast(channel, {:input_result, old_command.ref, input, :ok})
    send(channel, {:input_expired, old_command.ref})
    assert :sys.get_state(channel).input.command.ref == new_command.ref
    refute_received {:input_finished, :second, _result}

    send(provider, :release_input)
    assert_receive {:input_finished, :second, :ok}, 500
    Task.await(second)
    _ = :sys.get_state(input)
    refute_received {:probe_input, ^provider}
    assert GenServer.whereis(Input.address(allocation)) == input
  end

  test "a retired allocation envelope cannot consume replacement readiness credit" do
    tree = start_supervised!({CapabilityTree, owner: self()})
    scope = CapabilityTree.scope(tree)
    {:ok, old, :starting} = Session.start(scope, provider: SpeechDeferredSTT)
    assert_receive {:vxpipe_speech, old_ready}, 500
    assert :ok = Session.close(old)

    {:ok, replacement, :starting} = Session.start(scope, provider: SpeechDeferredSTT)
    assert_receive {:vxpipe_speech, ready}, 500
    assert {:error, :stale_event} = Session.ack(replacement, old_ready)
    assert :ok = Session.ack(replacement, ready)
    assert :ok = Session.push_audio(replacement, <<0, 0>>)
  end

  defp deferred_session do
    tree = start_supervised!({CapabilityTree, owner: self()})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree), provider: SpeechDeferredSTT)

    assert_receive {:vxpipe_speech, ready}, 500
    assert :ok = Session.ack(allocation, ready)
    {allocation, Session.provider(allocation)}
  end

  defp accept(usage, :ok), do: SpeechToTextSession.accept_input(usage, @observed_at)
  defp accept(usage, {:error, _reason}), do: {usage, []}

  defp usage do
    {:ok, provider} = ProviderContext.new(name: "morse_code", model: "morse_code")

    SpeechToTextSession.start(
      %{
        tenant_id: "tenant-usage",
        room_id: "room-usage",
        incarnation_id: "incarnation-usage",
        participant_id: "caller-usage"
      },
      "attempt-usage",
      "interval-usage",
      "call-usage",
      nil,
      provider
    )
  end
end
