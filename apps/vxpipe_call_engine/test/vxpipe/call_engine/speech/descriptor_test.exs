defmodule Vxpipe.CallEngine.Speech.DescriptorTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSession
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Descriptor, Event, Session}
  alias Vxpipe.CallEngine.SpeechSessionProbe

  test "validates the closed STT metadata boundary without exposing public settings" do
    {:ok, descriptor} = MorseSession.configure([])
    fields = descriptor |> Map.from_struct() |> Map.to_list()
    assert {:ok, ^descriptor} = Descriptor.new(fields)
    assert :ok = Descriptor.validate(descriptor)

    assert {:ok, _opus} =
             Descriptor.new(
               Keyword.put(fields, :format, %{
                 encoding: :opus,
                 container: :raw,
                 sample_rate: 48_000,
                 channels: 1
               })
             )

    refute inspect(%{descriptor | settings: %{secret: "synthetic-settings-sentinel"}}) =~
             "synthetic-settings-sentinel"

    for invalid <- [
          %{descriptor | kind: :other},
          %{descriptor | format: Map.put(descriptor.format, :headers, ["synthetic-header"])},
          %{descriptor | format: %{descriptor.format | container: :wav}},
          %{descriptor | format: %{descriptor.format | sample_rate: 0}},
          %{descriptor | format: %{descriptor.format | channels: 2}},
          %{descriptor | readiness: :connected},
          %{descriptor | endpointing: :unknown},
          %{descriptor | speech_start?: :maybe},
          %{descriptor | eager_end?: 1},
          %{descriptor | resume?: nil},
          %{
            descriptor
            | usage_identity: Map.put(descriptor.usage_identity, :api_key, "synthetic-key")
          },
          %{
            descriptor
            | usage_identity: %{descriptor.usage_identity | provider: "https://private.invalid"}
          },
          %{
            descriptor
            | usage_identity: %{descriptor.usage_identity | model: String.duplicate("x", 257)}
          },
          Map.put(descriptor, :unexpected, :field),
          %{},
          nil
        ] do
      assert {:error, :invalid_descriptor} = Descriptor.validate(invalid)
    end

    assert {:error, :invalid_descriptor} = Descriptor.new(kind: :stt, kind: :stt)
  end

  test "engine rejects an invalid descriptor before starting provider work" do
    tree = start_supervised!({CapabilityTree, owner: self()})
    {:ok, descriptor} = MorseSession.configure([])
    invalid = %{descriptor | format: %{descriptor.format | channels: 2}}

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: SpeechSessionProbe,
        options: [descriptor: invalid],
        private: [observer: self()]
      )

    assert_receive {:vxpipe_speech_closed, ^allocation, :initialization_failed}, 500
    refute_received {:probe_initializing, _pid, _channel}
    refute_received {:vxpipe_speech, _event}
  end

  test "finite-input completion is admitted only by a declaring STT descriptor and remains ordered" do
    tree = start_supervised!({CapabilityTree, owner: self()})
    {:ok, descriptor} = MorseSession.configure([])
    descriptor = Map.put(descriptor, :finite_input?, true)
    assert :ok = Descriptor.validate(descriptor)

    assert {:error, :invalid_descriptor} =
             Descriptor.validate(Map.put(descriptor, :finite_input?, :maybe))

    {:ok, generator} = Vxpipe.Providers.MorseCode.STSSession.configure([])
    assert {:error, :invalid_descriptor} = Descriptor.validate(%{generator | finite_input?: true})

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: SpeechSessionProbe,
        options: [descriptor: descriptor],
        private: [observer: self()]
      )

    assert_receive {:probe_initializing, provider, _}, 500
    assert_receive {:vxpipe_speech, ready}, 500
    assert :ok = Session.ack(allocation, ready)

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :turn_ended,
                [turn_ref: make_ref(), text: "SEGMENT", endpointing: :provider_gap]}
             )

    assert :ok = GenServer.call(provider, {:emit, :input_finished, []})
    assert_receive {:vxpipe_speech, %Event{kind: :turn_ended} = segment}
    refute_received {:vxpipe_speech, %Event{kind: :input_finished}}
    assert :ok = Session.ack(allocation, segment)
    assert_receive {:vxpipe_speech, %Event{kind: :input_finished} = finished}
    assert :ok = Session.ack(allocation, finished)
    refute Event.supported?(finished, Map.put(descriptor, :finite_input?, false))
    assert {:error, :invalid_event} = Event.build(:input_finished, text: "not a segment")
  end

  test "eager-end support requires provider-owned endpointing evidence" do
    {:ok, descriptor} = MorseSession.configure([])

    for endpointing <- [:none, :external] do
      assert :ok = Descriptor.validate(%{descriptor | endpointing: endpointing})

      assert {:error, :invalid_descriptor} =
               Descriptor.validate(%{descriptor | endpointing: endpointing, eager_end?: true})
    end
  end

  test "ready evidence must match the configured descriptor before activation" do
    tree = start_supervised!({CapabilityTree, owner: self()})
    {:ok, descriptor} = MorseSession.configure([])
    descriptor = %{descriptor | readiness: :provider_acknowledged}

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: SpeechSessionProbe,
        options: [descriptor: descriptor],
        private: [observer: self()]
      )

    # Provider death and initializer failure are independent safe-close signals.
    assert_receive {:vxpipe_speech_closed, ^allocation, reason}, 500
    assert reason in [:initialization_failed, :session_failed]
    assert {:error, :closed} = Session.push_audio(allocation, <<0, 0>>)
    refute_received {:vxpipe_speech, _event}
  end

  test "event provenance and optional evidence cannot exceed the advertised contract" do
    tree = start_supervised!({CapabilityTree, owner: self()})
    {:ok, descriptor} = MorseSession.configure([])
    descriptor = %{descriptor | speech_start?: false}

    {:ok, allocation, :starting} =
      Session.start(CapabilityTree.scope(tree),
        provider: SpeechSessionProbe,
        options: [descriptor: descriptor],
        private: [observer: self()]
      )

    assert_receive {:probe_initializing, provider, _channel}, 500
    assert_receive {:vxpipe_speech, ready}, 500
    assert :ok = Session.ack(allocation, ready)
    turn = make_ref()

    assert {:error, :invalid_event} =
             GenServer.call(provider, {:emit, :speech_started, [turn_ref: turn]})

    assert {:error, :invalid_event} =
             GenServer.call(
               provider,
               {:emit, :turn_ended, [turn_ref: turn, text: "E", endpointing: :provider_semantic]}
             )

    refute_received {:vxpipe_speech, _event}

    assert :ok =
             GenServer.call(
               provider,
               {:emit, :turn_ended, [turn_ref: turn, text: "E", endpointing: :provider_gap]}
             )

    assert_receive {:vxpipe_speech, %Event{kind: :turn_ended} = event}, 500
    assert :ok = Session.ack(allocation, event)
  end
end
