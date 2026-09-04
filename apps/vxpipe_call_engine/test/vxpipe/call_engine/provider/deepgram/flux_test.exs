defmodule Vxpipe.CallEngine.Provider.Deepgram.FluxTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Provider.Deepgram.Flux
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal

  describe "decode/1" do
    test "maps the Flux turn state machine without collapsing turn boundaries" do
      assert {:ok, %Signal{kind: :connected, provider_sequence: 0}} =
               Flux.decode(
                 JSON.encode!(%{
                   "type" => "Connected",
                   "request_id" => "request-1",
                   "sequence_id" => 0
                 })
               )

      assert {:ok,
              %Signal{
                kind: :turn_started,
                provider_sequence: 1,
                provider_turn_index: 0,
                text: "hello"
              }} = decode_turn("StartOfTurn", 1, "hello")

      assert {:ok,
              %Signal{
                kind: :transcript_updated,
                provider_sequence: 2,
                provider_turn_index: 0,
                text: "hello there"
              }} = decode_turn("Update", 2, "hello there")

      assert {:ok, %Signal{kind: :eager_turn_ended, text: "hello there"}} =
               decode_turn("EagerEndOfTurn", 3, "hello there")

      assert {:ok, %Signal{kind: :turn_resumed, text: "hello there again"}} =
               decode_turn("TurnResumed", 4, "hello there again")

      assert {:ok,
              %Signal{
                kind: :turn_ended,
                provider_sequence: 5,
                provider_turn_index: 0,
                text: "hello there again",
                trigger: "model"
              }} = decode_turn("EndOfTurn", 5, "hello there again", "model")
    end

    test "rejects malformed and oversized messages without retaining provider payloads" do
      assert {:error, :invalid_message} = Flux.decode(~s({"type":"TurnInfo"}))
      assert {:error, :invalid_json} = Flux.decode("not-json")

      assert {:error, :message_too_large} =
               Flux.decode(String.duplicate("x", Flux.maximum_message_bytes() + 1))

      assert {:ignore, :unknown_message} =
               Flux.decode(JSON.encode!(%{"type" => "FutureMessage", "secret" => "discard"}))
    end

    test "normalizes fatal errors to a bounded code" do
      assert {:ok,
              %Signal{
                kind: :failed,
                provider_sequence: 9,
                provider_code: "AUTHORIZATION_ERROR"
              }} =
               Flux.decode(
                 JSON.encode!(%{
                   "type" => "Error",
                   "sequence_id" => 9,
                   "code" => "AUTHORIZATION_ERROR",
                   "description" => "provider detail must not cross the adapter"
                 })
               )

      long_code = String.duplicate("x", Signal.maximum_provider_code_bytes() + 1)

      assert {:error, :invalid_message} =
               Flux.decode(
                 JSON.encode!(%{
                   "type" => "Error",
                   "sequence_id" => 10,
                   "code" => long_code,
                   "description" => "discard"
                 })
               )
    end
  end

  describe "connection_options/1" do
    test "keeps authorization out of the URL and configures raw browser Opus" do
      assert {:ok, config} =
               Flux.new(
                 api_key: "runtime-secret",
                 model: "flux-general-en",
                 encoding: :opus,
                 sample_rate: 48_000
               )

      assert %{url: url, headers: [{"Authorization", "Token runtime-secret"}]} =
               Flux.connection_options(config)

      refute url =~ "runtime-secret"

      assert %{
               "encoding" => "opus",
               "model" => "flux-general-en",
               "sample_rate" => "48000"
             } = url |> URI.new!() |> Map.fetch!(:query) |> URI.decode_query()
    end
  end

  defp decode_turn(event, sequence, transcript, trigger \\ nil) do
    message = %{
      "type" => "TurnInfo",
      "request_id" => "request-1",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    }

    message = if trigger == nil, do: message, else: Map.put(message, "trigger", trigger)
    Flux.decode(JSON.encode!(message))
  end
end
