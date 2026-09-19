defmodule Vxpipe.CallEngine.Speech.EventContractTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}
  alias Vxpipe.CallEngine.SpeechSessionProbe

  test "genuine provider identifiers are optional bounded nonempty UTF-8" do
    for value <- ["", <<255>>, String.duplicate("x", 257)] do
      assert {:error, :invalid_event} =
               Event.build(:ready, readiness: :initialized, provider_request_id: value)
    end

    assert {:ok, event} =
             Event.build(:ready,
               readiness: :initialized,
               provider_request_id: "synthetic-provider-id"
             )

    refute inspect(event) =~ "synthetic-provider-id"
    assert {:ok, %{provider_request_id: nil}} = Event.build(:ready, readiness: :initialized)
  end

  test "optional eager and resumed events require descriptor evidence" do
    tree = start_supervised!({CapabilityTree, owner: self()})
    scope = CapabilityTree.scope(tree)
    {:ok, descriptor} = MorseSession.configure([])
    turn = make_ref()

    for enabled? <- [false, true] do
      descriptor = %{descriptor | eager_end?: enabled?, resume?: enabled?}

      {:ok, allocation, :starting} =
        Session.start(scope,
          provider: SpeechSessionProbe,
          options: [descriptor: descriptor],
          private: [observer: self()]
        )

      assert_receive {:probe_initializing, provider, _channel}, 500
      assert_receive {:vxpipe_speech, ready}, 500
      assert :ok = Session.ack(allocation, ready)

      events = [
        {:eager_turn_ended, [turn_ref: turn, text: "E", endpointing: :provider_gap]},
        {:turn_resumed, [turn_ref: turn]}
      ]

      for {kind, fields} <- events do
        result = GenServer.call(provider, {:emit, kind, fields})

        if enabled? do
          assert result == :ok
          assert_receive {:vxpipe_speech, %Event{kind: ^kind, turn_ref: ^turn} = event}, 500
          assert :ok = Session.ack(allocation, event)
        else
          assert result == {:error, :invalid_event}
          refute_received {:vxpipe_speech, _event}
        end
      end

      assert :ok = Session.close(allocation)
    end
  end
end
