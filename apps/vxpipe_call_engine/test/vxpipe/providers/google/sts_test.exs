defmodule Vxpipe.Providers.Google.STSTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Google.STS

  test "large wire audio parts preserve their non-full PCM tail" do
    pcm = :binary.copy(<<42, 0>>, 65_536) <> <<7, 0, 8, 0>>

    payload =
      JSON.encode!(%{
        "serverContent" => %{
          "modelTurn" => %{
            "parts" => [
              %{
                "inlineData" => %{
                  "mimeType" => "audio/pcm;rate=24000",
                  "data" => Base.encode64(pcm)
                }
              }
            ]
          }
        }
      })

    assert {:ok, events} = STS.decode(payload)
    chunks = Enum.map(events, fn {:audio, audio} -> audio end)
    assert IO.iodata_to_binary(chunks) == pcm
    assert Enum.map(chunks, &byte_size/1) == [131_072, 4]
  end

  test "public options pin the live model with 16k input and 24k output" do
    assert {:ok, public} = STS.public_options(model: "gemini-3.8-live", voice: "Kore")
    assert public.model == "gemini-3.8-live"
    assert public.voice == "Kore"
    assert public.input_sample_rate == 16_000
    assert public.output_sample_rate == 24_000

    assert {:error, :invalid_configuration} =
             STS.public_options(model: "gemini-2.0-flash", voice: "Kore")

    assert {:error, :invalid_configuration} =
             STS.public_options(model: "gemini-3.8-live", voice: "")
  end

  test "setup enables both transcriptions with the selected turn control" do
    {:ok, config} = STS.new(api_key: "synthetic-key", model: "gemini-3.8-live", voice: "Kore")
    setup = STS.setup(config)
    assert setup["setup"]["model"] == "models/gemini-3.8-live"
    assert setup["setup"]["inputAudioTranscription"] == %{}
    assert setup["setup"]["outputAudioTranscription"] == %{}
    assert setup["setup"]["sessionResumption"] == %{}
    assert get_in(setup, ["setup", "generationConfig", "responseModalities"]) == ["AUDIO"]

    {:ok, manual} =
      STS.new(
        api_key: "synthetic-key",
        model: "gemini-3.8-live",
        voice: "Kore",
        turn_control: "external"
      )

    assert get_in(STS.setup(manual), ["setup", "automaticActivityDetection", "disabled"]) == true
  end

  test "audio encodes as 16k PCM and decodes 24k output in bounded chunks" do
    {:ok, encoded} = STS.encode_audio(:binary.copy(<<1, 0>>, 160))

    assert %{"realtimeInput" => %{"audio" => %{"mimeType" => "audio/pcm;rate=16000"}}} =
             JSON.decode!(encoded)

    assert {:error, :invalid_audio} = STS.encode_audio(<<1>>)
    assert {:error, :invalid_audio} = STS.encode_audio(:binary.copy(<<1, 0>>, 20_000))

    chunk = :binary.copy(<<2, 0>>, 400)

    payload =
      JSON.encode!(%{
        "serverContent" => %{
          "modelTurn" => %{
            "parts" => [
              %{
                "inlineData" => %{
                  "mimeType" => "audio/pcm;rate=24000",
                  "data" => Base.encode64(chunk)
                }
              }
            ]
          }
        }
      })

    assert {:ok, [{:audio, decoded}]} = STS.decode(payload)
    assert decoded == chunk
  end

  test "one message decodes every part: transcripts, audio, completion and interruption" do
    audio = :binary.copy(<<3, 0>>, 200)

    payload =
      JSON.encode!(%{
        "serverContent" => %{
          "activityStart" => true,
          "inputTranscription" => %{"text" => "hello"},
          "modelTurn" => %{
            "parts" => [
              %{
                "inlineData" => %{
                  "mimeType" => "audio/pcm;rate=24000",
                  "data" => Base.encode64(audio)
                }
              },
              %{"text" => "hi there"}
            ]
          },
          "outputTranscription" => %{"text" => "hi there"},
          "generationComplete" => true,
          "turnComplete" => true
        }
      })

    assert {:ok, events} = STS.decode(payload)
    assert :activity_start in events
    assert {:input_transcript, "hello"} in events
    assert {:audio, audio} in events
    assert {:output_transcript, "hi there"} in events
    assert :generation_complete in events
    assert :turn_complete in events
  end

  test "tool calls, cancellations, go-away, resumption and usage decode safely" do
    payload =
      JSON.encode!(%{
        "toolCall" => %{
          "functionCalls" => [%{"id" => "call-1", "name" => "echo", "args" => %{"text" => "hi"}}]
        },
        "toolCallCancellation" => %{"ids" => ["call-0"]},
        "goAway" => %{"timeLeft" => "60s"},
        "sessionResumptionUpdate" => %{
          "newHandle" => String.duplicate("h", 32),
          "resumable" => true
        },
        "usageMetadata" => %{"promptTokenCount" => 10, "responseTokenCount" => 20}
      })

    assert {:ok, events} = STS.decode(payload)
    assert {:tool_call, "call-1", "echo", %{"text" => "hi"}} in events
    assert {:tool_cancel, "call-0"} in events
    assert {:go_away, 60_000} in events
    assert {:resumption, String.duplicate("h", 32)} in events
    assert {:usage, %{"promptTokenCount" => 10, "responseTokenCount" => 20}} in events
  end

  test "malformed and oversized messages fail closed without credentials" do
    assert {:error, :invalid_message} = STS.decode("not json")
    assert {:error, :provider_failure} = STS.decode(JSON.encode!(%{"error" => %{"code" => 400}}))

    assert {:error, :invalid_message} =
             STS.decode(
               JSON.encode!(%{"serverContent" => %{"inputTranscription" => %{"text" => 1}}})
             )

    assert {:error, :invalid_message} = STS.decode(:binary.copy("x", 300_000))

    refute inspect(STS.new(api_key: "synthetic-key", model: "gemini-3.8-live", voice: "Kore")) =~
             "synthetic-key"
  end

  test "non-resumable updates revoke the previous handle, and malformed handles fail closed" do
    for update <- [%{"resumable" => false}, %{"resumable" => false, "newHandle" => ""}] do
      assert {:ok, [{:resumption, nil}]} =
               STS.decode(JSON.encode!(%{"sessionResumptionUpdate" => update}))
    end

    for update <- [
          %{"resumable" => true, "newHandle" => ""},
          %{"resumable" => true, "newHandle" => String.duplicate("x", 1_025)},
          %{"newHandle" => "missing-resumable-flag"}
        ] do
      assert {:error, :invalid_message} =
               STS.decode(JSON.encode!(%{"sessionResumptionUpdate" => update}))
    end
  end
end
