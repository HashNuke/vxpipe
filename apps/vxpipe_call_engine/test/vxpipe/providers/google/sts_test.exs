defmodule Vxpipe.Providers.Google.STSTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Google.STS

  test "new Gemini 3.x typed input uses the realtime text stream without history content" do
    assert {:ok, encoded} = STS.encode_text("genuinely new typed input")
    assert JSON.decode!(encoded) == %{"realtimeInput" => %{"text" => "genuinely new typed input"}}
  end

  test "model completion preserves explicit interaction state instead of implying idle" do
    for {wire, expected} <- [
          {"IDLE", :idle},
          {"IN_PROGRESS", :in_progress},
          {"INTERACTION_STATUS_UNSPECIFIED", :unknown},
          {"REQUIRES_ACTION", :requires_action}
        ] do
      assert {:ok, [{:turn_complete, ^expected}]} =
               STS.decode(
                 JSON.encode!(%{
                   "serverContent" => %{
                     "turnComplete" => true,
                     "interactionStatus" => wire
                   }
                 })
               )
    end

    assert {:ok, [{:turn_complete, :unknown}]} =
             STS.decode(JSON.encode!(%{"serverContent" => %{"turnComplete" => true}}))
  end

  test "interaction status requires a valid model-end envelope and closed wire enum" do
    for invalid <- [nil, 1, true, %{}, "idle", "FUTURE_STATUS"] do
      assert {:error, :invalid_message} =
               STS.decode(
                 JSON.encode!(%{
                   "serverContent" => %{
                     "turnComplete" => true,
                     "interactionStatus" => invalid
                   }
                 })
               )
    end

    assert {:error, :invalid_message} =
             STS.decode(JSON.encode!(%{"serverContent" => %{"interactionStatus" => "IDLE"}}))

    assert {:error, :invalid_message} =
             STS.decode(
               JSON.encode!(%{
                 "serverContent" => %{
                   "turnComplete" => false,
                   "interactionStatus" => "IDLE"
                 }
               })
             )
  end

  test "explicit false model completion has no terminal meaning" do
    assert {:ok, []} =
             STS.decode(JSON.encode!(%{"serverContent" => %{"turnComplete" => false}}))
  end

  test "thought-only model content signals private activity without spoken text" do
    assert {:ok, [:model_activity, :model_content]} =
             STS.decode(
               JSON.encode!(%{
                 "serverContent" => %{
                   "modelTurn" => %{
                     "parts" => [%{"text" => "private thought", "thought" => true}]
                   }
                 }
               })
             )
  end

  test "Gemini 3.x separates provisional input from its single final transcription" do
    assert {:ok, events} =
             STS.decode(
               JSON.encode!(%{
                 "serverContent" => %{
                   "interimInputTranscription" => %{"text" => "provisional"},
                   "inputTranscription" => %{"text" => "final caller text"}
                 }
               })
             )

    assert events == [
             {:input_transcript, "provisional", false},
             {:input_transcript, "final caller text", true}
           ]
  end

  test "interim input must satisfy the same bounded text contract as final input" do
    for invalid <- [nil, %{}, %{"text" => 42}, %{"text" => String.duplicate("x", 65_537)}] do
      assert {:error, :invalid_message} =
               STS.decode(
                 JSON.encode!(%{"serverContent" => %{"interimInputTranscription" => invalid}})
               )
    end
  end

  test "unproven hybrid control is rejected by public, private and descriptor configuration" do
    assert {:error, :invalid_configuration} = STS.public_options(turn_control: "hybrid")

    assert {:error, :invalid_configuration} =
             STS.new(api_key: "synthetic", turn_control: "hybrid")

    assert {:error, :invalid_configuration} =
             Vxpipe.Providers.Google.STSSession.configure(turn_control: "hybrid")

    for mode <- ["provider", "external"] do
      assert {:ok, descriptor} = Vxpipe.Providers.Google.STSSession.configure(turn_control: mode)
      assert descriptor.turn_control_supported == ["provider", "external"]
      assert {:ok, config} = STS.new(api_key: "synthetic", turn_control: mode)

      assert get_in(STS.setup(config), [
               "setup",
               "realtimeInputConfig",
               "automaticActivityDetection"
             ]) ==
               %{"disabled" => mode == "external"}
    end
  end

  test "tool names match the complete accepted alphabet without sanitization" do
    tool = %{
      "name" => "lookup",
      "description" => "synthetic",
      "parametersJsonSchema" => %{"type" => "object"}
    }

    assert {:ok, config} = STS.new(api_key: "synthetic", tools: [tool])

    for name <- [
          "lookup\n",
          "lookup\r\n",
          "lookup\nnext",
          " lookup",
          "lookup ",
          "",
          "lookup.name"
        ] do
      malformed = Map.put(tool, "name", name)
      assert {:error, :invalid_configuration} = STS.new(api_key: "synthetic", tools: [malformed])
      assert {:error, :invalid_configuration} = STS.validate(%{config | tools: [malformed]})
    end

    accepted = Map.put(tool, "name", "0_lookup-ABC")
    assert {:ok, valid} = STS.new(api_key: "synthetic", tools: [accepted])
    assert STS.setup(valid)["setup"]["tools"] == [%{"functionDeclarations" => [accepted]}]
  end

  test "private prompt and exact JSON tool schema reach setup without inspect disclosure" do
    tool = %{
      "name" => "lookup",
      "description" => "private-schema-marker",
      "parametersJsonSchema" => %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "enum" => ["private-enum-marker"]}
        },
        "required" => ["query"],
        "additionalProperties" => false
      }
    }

    assert {:ok, config} =
             STS.new(api_key: "synthetic", system_prompt: "private-prompt-marker", tools: [tool])

    assert STS.setup(config)["setup"]["tools"] == [%{"functionDeclarations" => [tool]}]

    assert STS.setup(config)["setup"]["systemInstruction"] == %{
             "parts" => [%{"text" => "private-prompt-marker"}]
           }

    refute inspect(config) =~ "private-"
  end

  test "private configuration rejects invalid schemas, duplicates and bounded payload overflow" do
    tool = %{
      "name" => "lookup",
      "description" => "lookup",
      "parametersJsonSchema" => %{"type" => "object"}
    }

    for overrides <- [
          [system_prompt: <<255>>],
          [system_prompt: 42],
          [system_prompt: String.duplicate("x", 65_537)],
          [tools: [Map.put(tool, "parametersJsonSchema", %{"type" => "string"})]],
          [
            tools: [
              Map.put(tool, "parametersJsonSchema", %{"type" => "object", "properties" => 1})
            ]
          ],
          [
            tools: [
              Map.put(tool, "parametersJsonSchema", %{"type" => "object", "private" => self()})
            ]
          ],
          [tools: [Map.put(tool, "behavior", "NON_BLOCKING")]],
          [tools: [tool, tool]],
          [tools: List.duplicate(tool, 65)],
          [tools: [Map.put(tool, "description", String.duplicate("x", 131_073))]]
        ] do
      assert {:error, :invalid_configuration} = STS.new([api_key: "synthetic"] ++ overrides)
    end

    assert {:error, :invalid_configuration} = STS.public_options(system_prompt: "private")
    assert {:error, :invalid_configuration} = STS.public_options(tools: [tool])
  end

  test "private configuration cannot be tampered after validation" do
    assert {:ok, config} = STS.new(api_key: "synthetic")
    assert :ok = STS.validate(config)

    for bad <- [
          %{config | system_prompt: <<255>>},
          %{config | tools: [%{}]},
          %{config | endpoint: "wss://unsupported.invalid"},
          %{config | api_key: ""}
        ] do
      assert {:error, :invalid_configuration} = STS.validate(bad)
    end
  end

  test "configuration bounds include aggregate size, JSON escaping and tool count" do
    tool = %{
      "name" => "lookup",
      "description" => "lookup",
      "parametersJsonSchema" => %{"type" => "object", "properties" => %{}}
    }

    tools = for index <- 1..64, do: Map.put(tool, "name", "lookup_#{index}")

    assert {:ok, _} =
             STS.new(
               api_key: "synthetic",
               tools: tools,
               system_prompt: String.duplicate("x", 65_536)
             )

    assert {:error, :invalid_configuration} =
             STS.new(api_key: "synthetic", tools: tools ++ [Map.put(tool, "name", "extra")])

    assert {:error, :invalid_configuration} =
             STS.new(api_key: "synthetic", system_prompt: String.duplicate(<<0>>, 65_536))

    large_tools =
      Enum.map(tools, fn tool ->
        put_in(tool, ["parametersJsonSchema", "description"], String.duplicate("x", 3_000))
      end)

    assert {:error, :invalid_configuration} = STS.new(api_key: "synthetic", tools: large_tools)

    assert {:error, :invalid_configuration} =
             STS.new(api_key: "synthetic", tools: [], tools: tools)

    assert {:error, :invalid_configuration} =
             STS.new(api_key: "synthetic", endpoint: "wss://unsupported.invalid")
  end

  test "setup nests activity detection under the documented realtime input configuration" do
    assert {:ok, config} = STS.new(api_key: "synthetic", turn_control: "external")
    setup = STS.setup(config)["setup"]

    assert setup["realtimeInputConfig"] == %{
             "automaticActivityDetection" => %{"disabled" => true}
           }

    refute Map.has_key?(setup, "automaticActivityDetection")
  end

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

    assert {:ok, [:model_activity, :model_content | events]} = STS.decode(payload)
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

    assert get_in(STS.setup(manual), [
             "setup",
             "realtimeInputConfig",
             "automaticActivityDetection",
             "disabled"
           ]) == true
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

    assert {:ok, [:model_activity, :model_content, {:audio, decoded}]} = STS.decode(payload)
    assert decoded == chunk
  end

  test "raw v1beta voiceActivity.type decodes start and end independently" do
    for {type, event} <- [{"ACTIVITY_START", :activity_start}, {"ACTIVITY_END", :activity_end}],
        offset <- [nil, "0s", "1.250s"] do
      activity = %{"type" => type}
      activity = if offset, do: Map.put(activity, "audioOffset", offset), else: activity
      assert {:ok, [^event]} = STS.decode(JSON.encode!(%{"voiceActivity" => activity}))
    end

    for activity <- [%{}, %{"type" => "TYPE_UNSPECIFIED"}] do
      assert {:ok, []} = STS.decode(JSON.encode!(%{"voiceActivity" => activity}))
    end
  end

  test "SDK-only activity keys are rejected even beside a valid raw type" do
    for activity <- [
          %{"voiceActivityType" => "ACTIVITY_START"},
          %{"voice_activity_type" => "ACTIVITY_END"},
          %{"type" => "ACTIVITY_START", "voiceActivityType" => "ACTIVITY_END"},
          %{"type" => "ACTIVITY_START", "voiceActivityType" => "ACTIVITY_START"},
          %{"type" => "ACTIVITY_END", "audio_offset" => "1s"}
        ] do
      assert {:error, :invalid_message} = STS.decode(JSON.encode!(%{"voiceActivity" => activity}))
    end
  end

  test "malformed known voice activity fields fail without emitting partial events" do
    for activity <- [
          nil,
          true,
          [],
          "ACTIVITY_START",
          %{"type" => nil},
          %{"type" => 1},
          %{"type" => %{}},
          %{"type" => "UNKNOWN"},
          %{"type" => "ACTIVITY_START\n"},
          %{"type" => "ACTIVITY_START", "audioOffset" => 1},
          %{"type" => "ACTIVITY_END", "audioOffset" => nil},
          %{"type" => "ACTIVITY_START", "audioOffset" => String.duplicate("x", 65_537)},
          %{"audioOffset" => %{}}
        ] do
      assert {:error, :invalid_message} =
               STS.decode(
                 JSON.encode!(%{
                   "voiceActivity" => activity,
                   "serverContent" => %{"turnComplete" => true}
                 })
               )
    end
  end

  test "client activity fields and allowlisted detection signal are not server boundaries" do
    assert {:ok, []} =
             STS.decode(
               JSON.encode!(%{
                 "serverContent" => %{
                   "activityStart" => true,
                   "activityEnd" => true,
                   "speechState" => "SPEECH_START"
                 },
                 "voiceActivityDetectionSignal" => %{"vadSignalType" => "VAD_SIGNAL_TYPE_SOS"}
               })
             )
  end

  test "one message decodes every part: transcripts, audio, completion and interruption" do
    audio = :binary.copy(<<3, 0>>, 200)

    payload =
      JSON.encode!(%{
        "voiceActivity" => %{"type" => "ACTIVITY_START"},
        "serverContent" => %{
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
    assert {:input_transcript, "hello", true} in events
    assert {:audio, audio} in events
    assert {:output_transcript, "hi there"} in events
    assert :generation_complete in events
    assert {:turn_complete, :unknown} in events
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
