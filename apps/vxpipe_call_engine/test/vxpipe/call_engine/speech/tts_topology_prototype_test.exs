defmodule Vxpipe.CallEngine.Speech.TTSTopologyPrototypeTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.SpeechSessionOwner
  alias Vxpipe.CallEngine.SpeechTopologyPrototype, as: Prototype

  setup do
    registry = start_supervised!({Registry, keys: :unique, name: Prototype.registry()})

    sessions =
      start_supervised!({DynamicSupervisor, name: Prototype.sessions(), strategy: :one_for_one})

    %{registry: registry, sessions: sessions}
  end

  for topology <- [:split, :merged] do
    @topology topology

    test "#{topology} topology preserves native Morse, authority and replacement isolation" do
      owner = start_supervised!({SpeechSessionOwner, self()}, id: {@topology, :owner})
      stt = start_supervised!(Prototype.stt_child_spec(self()))
      usage = start_supervised!(Prototype.usage_child_spec())
      session = Prototype.start!(@topology, owner, usage, self())

      on_exit(fn -> Prototype.close(session) end)

      assert :ok = run(owner, fn -> Prototype.prepare(session) end)
      event(owner, session, nil, :ready)

      assert {:error, :not_owner} = Prototype.speak(session, "E", hold_result?: true)

      assert {:ok, first} =
               run(owner, fn -> Prototype.speak(session, "E", hold_result?: true) end)

      submitted = event(owner, session, first, :input_submitted)
      assert is_binary(submitted.provider_request_id)

      assert {:ok, first_fact} = Prototype.take_usage(usage, first)
      assert first_fact.input_characters == 1
      assert first_fact.provider_request_id == submitted.provider_request_id
      assert first_fact.provenance == :locally_measured

      assert_receive {:speech_owner, ^owner, {:topology_audio, first_audio}}
      assert first_audio.request_ref == first
      assert first_audio.payload == binary_part(Prototype.pcm("E"), 0, 320)
      assert :ok = run(owner, fn -> Prototype.validate_audio(session, first_audio) end)
      assert_receive {:speech_owner, ^owner, {:topology_input_held, input, hold}}

      turn = make_ref()
      assert :ok = Prototype.stt_turn(stt, turn, Prototype.pcm("E"))
      assert_receive {:topology_speech_started, ^turn}
      assert_receive {:topology_text, ^turn, "E"}
      assert_receive {:topology_turn_end, ^turn, "E"}

      assert {:ok, fence} = run(owner, fn -> Prototype.fence(session, first) end)

      cancel = Task.async(fn -> run(owner, fn -> Prototype.cancel(session, fence, 10) end) end)
      assert_receive {:topology_cancel_queued, ^first}

      Prototype.release(input, hold)

      assert {:ok, %{request_ref: ^first, played_ms: 10, session_played_ms: 10}} =
               Task.await(cancel, 1_000)

      event(owner, session, first, :cancelled)

      assert {:ok, replacement} = run(owner, fn -> Prototype.speak(session, "T") end)
      assert replacement != first
      replacement_submitted = event(owner, session, replacement, :input_submitted)
      assert is_binary(replacement_submitted.provider_request_id)

      expected = Prototype.pcm("T")
      assert collect_audio(owner, session, replacement, byte_size(expected), []) == expected
      event(owner, session, replacement, :completed)

      assert {:ok, replacement_fence} =
               run(owner, fn -> Prototype.fence(session, replacement) end)

      assert {:ok, %{request_ref: ^replacement, session_played_ms: 10}} =
               run(owner, fn -> Prototype.cancel(session, replacement_fence, 0) end)

      assert :ok = run(owner, fn -> Prototype.sync(session) end)
      refute_received {:speech_owner, ^owner, {:topology_audio, _stale}}
      refute_received {:speech_owner, ^owner, {:topology_event, _duplicate}}
      assert Prototype.process_count(session) == if(@topology == :split, do: 4, else: 3)

      tree_monitor = Process.monitor(session.supervisor)
      Process.exit(session.channel, :kill)
      assert_receive {:DOWN, ^tree_monitor, :process, _, _}, 500

      later_turn = make_ref()
      assert :ok = Prototype.stt_turn(stt, later_turn, Prototype.pcm("T"))
      assert_receive {:topology_speech_started, ^later_turn}
      assert_receive {:topology_text, ^later_turn, "T"}
      assert_receive {:topology_turn_end, ^later_turn, "T"}

      assert {:ok, replacement_fact} = Prototype.take_usage(usage, replacement)
      assert replacement_fact.provider_request_id == replacement_submitted.provider_request_id
    end

    test "#{topology} topology retires only its disposable tree on fixed watchdog expiry" do
      owner = start_supervised!({SpeechSessionOwner, self()}, id: {@topology, :watchdog_owner})
      stt = start_supervised!(Prototype.stt_child_spec(self()))
      usage = start_supervised!(Prototype.usage_child_spec())
      session = Prototype.start!(@topology, owner, usage, self())

      assert :ok = run(owner, fn -> Prototype.prepare(session) end)
      event(owner, session, nil, :ready)
      assert {:ok, request} = run(owner, fn -> Prototype.speak(session, "E") end)
      event(owner, session, request, :input_submitted)
      assert_receive {:speech_owner, ^owner, {:topology_audio, audio}}

      tree_monitor = Process.monitor(session.supervisor)
      target = session.output || session.channel
      send(target, {:credit_expired, audio.ref})
      assert_receive {:DOWN, ^tree_monitor, :process, _, _}, 500

      turn = make_ref()
      assert :ok = Prototype.stt_turn(stt, turn, Prototype.pcm("E"))
      assert_receive {:topology_speech_started, ^turn}
      assert_receive {:topology_text, ^turn, "E"}
      assert_receive {:topology_turn_end, ^turn, "E"}

      replacement = Prototype.start!(@topology, owner, usage, self())
      assert :ok = run(owner, fn -> Prototype.prepare(replacement) end)
      event(owner, replacement, nil, :ready)
      assert {:ok, next_request} = run(owner, fn -> Prototype.speak(replacement, "T") end)
      event(owner, replacement, next_request, :input_submitted)
      assert_receive {:speech_owner, ^owner, {:topology_audio, _next_audio}}

      assert {:ok, ticket} =
               run(owner, fn -> Prototype.fence(replacement, next_request) end)

      replacement_monitor = Process.monitor(replacement.supervisor)
      send(replacement.channel, {:cancellation_expired, ticket.ref})
      assert_receive {:DOWN, ^replacement_monitor, :process, _, _}, 500
    end
  end

  defp event(owner, session, request, kind) do
    assert_receive {:speech_owner, ^owner, {:topology_event, event}}, 1_000
    assert event.kind == kind
    assert event.request_ref == request
    assert :ok = run(owner, fn -> Prototype.ack_event(session, event) end)
    event
  end

  defp collect_audio(_owner, _session, _request, 0, chunks),
    do: chunks |> Enum.reverse() |> IO.iodata_to_binary()

  defp collect_audio(owner, session, request, remaining, chunks) do
    assert_receive {:speech_owner, ^owner, {:topology_audio, audio}}, 1_000
    assert audio.request_ref == request
    assert byte_size(audio.payload) <= remaining
    assert :ok = run(owner, fn -> Prototype.validate_audio(session, audio) end)
    assert :ok = run(owner, fn -> Prototype.ack_audio(session, audio) end)

    collect_audio(owner, session, request, remaining - byte_size(audio.payload), [
      audio.payload | chunks
    ])
  end

  defp run(owner, operation), do: SpeechSessionOwner.run(owner, fn _ -> operation.() end)
end
