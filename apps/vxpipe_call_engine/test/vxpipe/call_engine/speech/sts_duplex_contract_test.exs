defmodule Vxpipe.CallEngine.Speech.STSDuplexContractTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Archive.EventProjection
  alias Vxpipe.CallEngine.Event.{AgentTurnCompleted, ParticipantTurnCompleted}
  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: MorseSTT
  alias Vxpipe.CallEngine.Provider.MorseCodeSTS.Session, as: MorseSTS
  alias Vxpipe.CallEngine.Speech.{Descriptor, Event}

  describe "descriptor duplex facts" do
    test "existing STS descriptors keep the room-owned defaults" do
      {:ok, descriptor} = MorseSTS.configure([])

      assert descriptor.output_shape == :turns
      assert descriptor.barge_in == :room
      assert descriptor.continuity == :resumption_handle
      assert descriptor.tool_cancellation? == true
      assert descriptor.hold == :stop
      assert :ok = Descriptor.validate(descriptor)

      {:ok, google} = Vxpipe.Providers.Google.STSSession.configure([])
      assert google.output_shape == :turns
      assert google.barge_in == :room
      assert google.continuity == :resumption_handle
      assert google.tool_cancellation? == true
      assert google.hold == :stop
      assert :ok = Descriptor.validate(google)
    end

    test "accepts a provider-owned duplex descriptor with inferred caller boundaries" do
      {:ok, base} = MorseSTS.configure([])

      descriptor =
        struct(base,
          endpointing: :inferred_gap,
          turn_control: "provider",
          output_shape: :continuous,
          barge_in: :provider,
          continuity: :history_reseed,
          tool_cancellation?: false,
          hold: :mute,
          history_reconciliation?: false
        )

      assert :ok = Descriptor.validate(descriptor)
    end

    test "inferred gaps require provider turn control and caller speech onset" do
      {:ok, base} = MorseSTS.configure([])

      for invalid <- [
            %{base | endpointing: :inferred_gap, turn_control: "external"},
            %{base | endpointing: :inferred_gap, turn_control: "hybrid"},
            %{base | endpointing: :inferred_gap, speech_start?: false}
          ] do
        assert {:error, :invalid_descriptor} = Descriptor.validate(invalid)
      end

      assert :ok =
               Descriptor.validate(%{
                 base
                 | endpointing: :inferred_gap,
                   turn_control: "provider",
                   speech_start?: true
               })
    end

    test "provider-owned barge-in forbids room history reconciliation" do
      {:ok, base} = MorseSTS.configure([])

      assert {:error, :invalid_descriptor} =
               Descriptor.validate(%{
                 base
                 | barge_in: :provider,
                   history_reconciliation?: true
               })

      assert :ok =
               Descriptor.validate(%{
                 base
                 | barge_in: :provider,
                   history_reconciliation?: false
               })
    end

    test "rejects unknown values for every closed duplex fact" do
      {:ok, base} = MorseSTS.configure([])

      for {field, value} <- [
            output_shape: :bursts,
            barge_in: :caller,
            continuity: :resume,
            hold: :pause,
            tool_cancellation?: :maybe
          ] do
        assert {:error, :invalid_descriptor} = Descriptor.validate(Map.put(base, field, value))
      end
    end

    test "non-STS descriptors cannot declare duplex facts" do
      {:ok, base} = MorseSTT.configure([])

      for facts <- [
            [output_shape: :continuous],
            [barge_in: :provider],
            [continuity: :history_reseed],
            [tool_cancellation?: false],
            [hold: :mute]
          ] do
        assert {:error, :invalid_descriptor} = Descriptor.validate(struct(base, facts))
      end

      assert :ok = Descriptor.validate(base)
    end
  end

  describe "event additions" do
    test "output transcript alignment fields are optional and bounded" do
      turn = make_ref()
      output = make_ref()

      assert {:ok, _event} =
               Event.build(:output_transcript,
                 turn_ref: turn,
                 text: "HI",
                 output_ref: output,
                 audio_start_ms: 0,
                 audio_end_ms: 400
               )

      assert {:ok, _event} = Event.build(:output_transcript, turn_ref: turn, text: "HI")

      for fields <- [
            [turn_ref: turn, text: "HI", output_ref: output],
            [turn_ref: turn, text: "HI", audio_start_ms: 0, audio_end_ms: 400],
            [
              turn_ref: turn,
              text: "HI",
              output_ref: "output",
              audio_start_ms: 0,
              audio_end_ms: 400
            ],
            [
              turn_ref: turn,
              text: "HI",
              output_ref: output,
              audio_start_ms: -1,
              audio_end_ms: 400
            ],
            [turn_ref: turn, text: "HI", output_ref: output, audio_start_ms: 400, audio_end_ms: 0]
          ] do
        assert {:error, :invalid_event} = Event.build(:output_transcript, fields)
      end
    end

    test "inferred gap is a valid inferred turn boundary" do
      turn = make_ref()

      assert {:ok, event} =
               Event.build(:turn_ended,
                 turn_ref: turn,
                 text: "HI",
                 endpointing: :inferred_gap
               )

      assert Event.supported?(event, %{kind: :sts, endpointing: :inferred_gap})
      refute Event.supported?(event, %{kind: :sts, endpointing: :provider_gap})

      assert {:error, :invalid_event} =
               Event.build(:turn_ended,
                 turn_ref: turn,
                 text: "HI",
                 endpointing: :guessed
               )
    end

    test "public agent turns carry an overlapped outcome and caller turns carry evidence" do
      completed = struct(AgentTurnCompleted, outcome: :overlapped)
      assert {:agent_turn_completed, payload} = EventProjection.project(completed)
      assert payload[:payload] == %{"outcome" => "overlapped"}

      inferred = struct(ParticipantTurnCompleted, endpointing: :inferred_gap, modality: :audio)
      assert {:participant_turn_completed, payload} = EventProjection.project(inferred)

      assert payload[:payload] == %{
               "modality" => :audio,
               "endpointing" => "inferred_gap"
             }
    end
  end
end
