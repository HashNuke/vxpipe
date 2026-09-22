defmodule Vxpipe.CallEngine.Speech.STSConformanceTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCodeSTS.Session, as: MorseSTS
  alias Vxpipe.CallEngine.Speech.{Descriptor, Event, Session}
  alias Vxpipe.CallEngine.SpeechProviderContract, as: Contract
  alias Vxpipe.CallEngine.SpeechSTSContractProvider, as: Provider

  test "audio and text driven STS turns deliver credited audio without a TTS request" do
    for input <- [:audio, :text] do
      session = start_session(usage: true)
      provider = Session.provider(session)

      case input do
        :audio ->
          assert :ok = Session.push_audio(session, <<0, 0>>)

        :text ->
          assert :ok = Session.push_text(session, "E")
          Contract.ack_event!(session, :input_submitted)
      end

      turn = make_ref()
      assert {:error, :stale_request} = GenServer.call(provider, {:output, turn})
      assert {:ok, output} = Session.admit_output(session, turn)
      reference = output.ref
      assert_receive {:sts_output_permitted, ^provider, channel, ^turn, ^reference}
      assert {:error, :busy} = Session.admit_output(session, make_ref())
      assert {:ok, credit} = GenServer.call(provider, {:output, reference})
      assert {:error, :busy} = GenServer.call(provider, {:output, reference})
      audio = Contract.next_audio!(session, reference, :binary.copy(<<0, 0>>, 320))
      assert audio.usage == nil
      assert {:error, :output_pending} = complete(provider, output)
      assert :ok = Session.ack_audio(session, audio)
      assert_receive {:vxpipe_speech_credit, ^channel, ^reference, ^credit, :ok}
      assert :ok = complete(provider, output)
      assert {:error, :output_pending} = Session.settle_output(session, output, 20)
      completed = Contract.ack_event!(session, :output_completed)
      assert completed.turn_ref == turn
      assert completed.request_ref == reference
      assert completed.usage == nil
      assert {:error, :busy} = Session.admit_output(session, make_ref())
      assert {:error, :invalid_playback} = Session.settle_output(session, output, 21)
      assert :ok = Session.settle_output(session, output, 20)
      assert {:error, :stale_request} = GenServer.call(provider, {:output, reference})
      assert {:ok, replacement} = Session.admit_output(session, turn)
      refute replacement.ref == reference
      assert {:error, :stale_request} = complete(provider, output)
      assert :ok = Session.close(session)
      assert {:error, :closed} = Session.admit_output(session, make_ref())
    end
  end

  test "duplicate submission evidence is rejected before and after the input callback returns" do
    session = start_session(mode: :duplicate)
    assert :ok = Session.push_text(session, "E")
    assert_receive {:text_submission, reference, [:ok, {:error, :stale_request}]}
    Contract.ack_event!(session, :input_submitted)

    assert {:error, :stale_request} =
             emit(session, :input_submitted,
               request_ref: reference,
               provenance: :locally_measured
             )

    refute_receive {:vxpipe_speech, %Event{kind: :input_submitted}}
    assert :ok = Session.push_audio(session, <<0, 0>>)
  end

  test "STS transcripts cannot bypass coverage with the generic STT event" do
    session = start_session(options: [input_transcript: false, output_transcript: false])

    for kind <- [:transcript, :input_transcript, :output_transcript] do
      assert {:error, :invalid_event} = emit(session, kind, turn_ref: make_ref(), text: "E")
    end

    refute_receive {:vxpipe_speech, %Event{}}
  end

  test "parameterized tools retain bounded arguments and the active turn through the channel" do
    session = start_session()
    turn = make_ref()
    call = make_ref()
    arguments = %{"order_id" => "123", "include" => ["status"], "details" => true}
    fields = [turn_ref: turn, call_ref: call, tool_name: "lookup_order", arguments: arguments]
    assert :ok = emit(session, :tool_call, fields)
    event = Contract.ack_event!(session, :tool_call)
    assert event.arguments == arguments
    assert event.turn_ref == turn
    assert event.call_ref == call
    refute inspect(event) =~ "order_id"

    maximum_arguments = %{"v" => [String.duplicate("x", 65_526)]}
    assert byte_size(JSON.encode!(maximum_arguments)) == 65_536
    assert :ok = emit(session, :tool_call, Keyword.put(fields, :arguments, maximum_arguments))
    assert Contract.ack_event!(session, :tool_call).arguments == maximum_arguments

    deeply_nested = Enum.reduce(1..17, %{}, fn _, nested -> %{"nested" => nested} end)

    for bad <- [
          nil,
          %{atom_key: "value"},
          %{"pid" => self()},
          %{"value" => <<255>>},
          %{"value" => String.duplicate("x", 65_537)},
          %{"value" => String.duplicate("\n", 32_768)},
          %{"improper" => [1 | 2]},
          %{"struct" => %URI{}},
          deeply_nested
        ] do
      assert {:error, :invalid_event} =
               emit(session, :tool_call, Keyword.put(fields, :arguments, bad))
    end

    assert {:error, :invalid_event} = emit(session, :tool_call, Keyword.delete(fields, :turn_ref))
    assert :ok = Session.push_audio(session, <<0, 0>>)
  end

  test "turn mode and endpointing evidence must describe a usable controller" do
    assert {:ok, descriptor} = MorseSTS.configure([])

    for mode <- ["provider", "hybrid"] do
      assert {:error, :invalid_descriptor} =
               Descriptor.validate(%{
                 descriptor
                 | turn_control: mode,
                   endpointing: :external,
                   speech_start?: false
               })
    end

    assert {:error, :invalid_descriptor} =
             Descriptor.validate(%{descriptor | turn_control_supported: ["provider", "unknown"]})

    assert {:ok, external} = MorseSTS.configure(turn_control: "external")
    assert external.endpointing == :external
    assert :ok = Descriptor.validate(external)
  end

  test "STS output descriptors require the PCM format used by the credited audio path" do
    assert {:ok, descriptor} = MorseSTS.configure([])
    opus = %{encoding: :opus, container: :raw, channels: 1, sample_rate: 48_000}
    assert {:error, :invalid_descriptor} = Descriptor.validate(%{descriptor | format: opus})
  end

  defp start_session(options \\ []) do
    mode = Keyword.get(options, :mode, :normal)

    Contract.start_profile!(
      Provider,
      Keyword.put(options, :private, observer: self(), mode: mode)
    )
  end

  defp emit(session, kind, fields),
    do: GenServer.call(Session.provider(session), {:emit, kind, fields})

  defp complete(provider, output),
    do:
      GenServer.call(
        provider,
        {:emit, :output_completed, [turn_ref: output.turn_ref, request_ref: output.ref]}
      )
end
