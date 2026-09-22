defmodule Vxpipe.Providers.Google.STSSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.Providers.Google.{STS, STSSession}
  alias Vxpipe.CallEngine.TestGoogleSTSTransport

  test "setup pins the live model with voice and transcriptions, keeping credentials private" do
    {_session, wire} = start_session()
    assert_receive {:test_google_sts_control, ^wire, setup}
    decoded = JSON.decode!(setup)
    assert decoded["setup"]["model"] == "models/gemini-3.8-live"
    assert decoded["setup"]["inputAudioTranscription"] == %{}
    assert decoded["setup"]["outputAudioTranscription"] == %{}
    assert get_in(decoded, ["setup", "generationConfig", "responseModalities"]) == ["AUDIO"]
    refute setup =~ "synthetic-google-sts-key"
  end

  test "input audio converts to 16k PCM and rejects malformed chunks" do
    {session, wire} = start_session()
    assert :ok = Session.push_audio(session, :binary.copy(<<1, 0>>, 160))
    assert_receive {:test_google_sts_audio, ^wire, _audio}
    assert {:error, :invalid_audio_size} = Session.push_audio(session, <<>>)
  end

  test "out-of-order transcripts and audio correlate to one turn with generation settlement" do
    {session, wire} = start_session()

    deliver(wire, %{"serverContent" => %{"outputTranscription" => %{"text" => "early text"}}})

    deliver(wire, %{
      "serverContent" => %{
        "activityStart" => true,
        "modelTurn" => %{
          "parts" => [
            %{
              "inlineData" => %{
                "mimeType" => "audio/pcm;rate=24000",
                "data" => Base.encode64(:binary.copy(<<4, 0>>, 200))
              }
            }
          ]
        }
      }
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)

    deliver(wire, %{
      "serverContent" => %{"inputTranscription" => %{"text" => "hello"}, "turnComplete" => true}
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript} = input}
    assert :ok = Session.ack(session, input)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :turn_ended, text: "hello"} = ended}

    assert :ok = Session.ack(session, ended)
    assert {:ok, output} = Session.admit_output(session, ended.turn_ref)

    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}
    assert :ok = Session.validate_audio(session, audio)
    assert :ok = Session.ack_audio(session, audio)

    deliver(wire, %{"serverContent" => %{"generationComplete" => true}})

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :output_completed} = done}
    assert :ok = Session.ack(session, done)
    assert :ok = Session.settle_output(session, output, 0)
  end

  test "interruption before first audio fences the turn without output" do
    {session, wire} = start_session()

    deliver(wire, %{"serverContent" => %{"activityStart" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)

    provider = Session.provider(session)
    assert :ok = STSSession.interrupt(provider, started.turn_ref)
    assert_receive {:test_google_sts_control, ^wire, _interrupt}

    deliver(wire, %{"serverContent" => %{"interrupted" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :interrupted} = interrupted}
    assert :ok = Session.ack(session, interrupted)
    refute_received {:vxpipe_speech_audio, _}
  end

  test "external turn control ignores wire activity and uses explicit boundaries" do
    {session, wire} = start_session(turn_control: "external")

    deliver(wire, %{"serverContent" => %{"activityStart" => true}})
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :speech_started}}

    assert :ok = Session.input_activity(session, :started)
    assert :ok = Session.input_activity(session, :ended)

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = ended}
    assert :ok = Session.ack(session, ended)
  end

  test "tool calls map provider ids to bounded results and cancellations" do
    {session, wire} = start_session()

    deliver(wire, %{"serverContent" => %{"activityStart" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)

    deliver(wire, %{
      "toolCall" => %{
        "functionCalls" => [
          %{"id" => "provider-1", "name" => "echo", "args" => %{"text" => "hi"}}
        ]
      }
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :tool_call} = call}
    assert :ok = Session.ack(session, call)
    assert call.tool_name == "echo"

    provider = Session.provider(session)
    assert :ok = STSSession.send_tool_result(provider, call.call_ref, %{"ok" => true})
    assert_receive {:test_google_sts_control, ^wire, response}, 5_000
    response = drain_until_tool_response(wire, response)
    assert response =~ "provider-1"

    assert {:error, :stale_request} = STSSession.send_tool_result(provider, make_ref(), %{})

    deliver(wire, %{"toolCallCancellation" => %{"ids" => ["provider-2"]}})
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :tool_cancelled}}
  end

  test "sent-ahead audio during the fence window is dropped before the next turn" do
    {session, wire} = start_session()

    deliver(wire, %{"serverContent" => %{"activityStart" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)

    provider = Session.provider(session)
    assert :ok = STSSession.interrupt(provider, started.turn_ref)

    deliver(wire, %{
      "serverContent" => %{
        "modelTurn" => %{
          "parts" => [
            %{
              "inlineData" => %{
                "mimeType" => "audio/pcm;rate=24000",
                "data" => Base.encode64(:binary.copy(<<5, 0>>, 200))
              }
            }
          ]
        },
        "generationComplete" => true
      }
    })

    deliver(wire, %{"serverContent" => %{"interrupted" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :interrupted} = interrupted}
    assert :ok = Session.ack(session, interrupted)

    deliver(wire, %{"serverContent" => %{"activityStart" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = next}
    assert :ok = Session.ack(session, next)
    assert next.turn_ref != started.turn_ref

    deliver(wire, %{
      "serverContent" => %{"inputTranscription" => %{"text" => "again"}, "turnComplete" => true}
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :input_transcript} = input}
    assert :ok = Session.ack(session, input)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :turn_ended, text: "again"} = ended}

    assert :ok = Session.ack(session, ended)
  end

  test "go-away without a resumption handle fails closed instead of restarting silently" do
    {session, wire} = start_session(resumption_timeout_ms: 50)
    monitor = session |> Session.tree() |> Process.monitor()
    deliver(wire, %{"goAway" => %{"timeLeft" => "60s"}})
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
  end

  test "renewal uses the latest handle and resumes the same allocation only after setup acknowledgement" do
    {session, wire} = start_session()
    old_monitor = Process.monitor(wire)
    handle = "synthetic-latest-handle"
    update_handle(session, wire, "synthetic-old-handle")
    update_handle(session, wire, handle)
    deliver(wire, %{"goAway" => %{"timeLeft" => "60s"}})

    assert_receive {:test_google_sts_started, pending, _connection}
    assert pending != wire
    assert_receive {:test_google_sts_control, ^pending, setup}
    assert get_in(JSON.decode!(setup), ["setup", "sessionResumption", "handle"]) == handle
    assert_receive {:DOWN, ^old_monitor, :process, ^wire, _reason}
    assert {:error, :busy} = Session.push_audio(session, <<1, 0>>)
    refute_received {:test_google_sts_audio, ^pending, _}

    deliver_sync(session, pending, %{"setupComplete" => %{}})
    assert :ok = Session.push_audio(session, <<2, 0>>)
    assert_receive {:test_google_sts_audio, ^pending, <<2, 0>>}
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :ready}}

    # Retired-socket events and timers cannot affect the adopted generation.
    provider = Session.provider(session)
    send(provider, {:vxpipe_sts_transport, wire, {:closed, :connection_lost}})
    send(provider, {:expire, wire})
    send(provider, {:vxpipe_sts_transport, wire, {:message, ~s({"error":{}})}})
    assert :ok = Session.push_audio(session, <<3, 0>>)
    assert_receive {:test_google_sts_audio, ^pending, <<3, 0>>}
    refute inspect(:sys.get_status(provider)) =~ handle
  end

  test "a revoked handle cannot be used after connection loss" do
    {session, wire} = start_session()
    monitor = session |> Session.tree() |> Process.monitor()
    update_handle(session, wire, "synthetic-revoked-handle")
    deliver_sync(session, wire, %{"sessionResumptionUpdate" => %{"resumable" => false}})
    TestGoogleSTSTransport.disconnect(wire)
    assert_receive {:DOWN, ^monitor, :process, _, _}
    refute_received {:test_google_sts_started, _, _}
  end

  test "connection loss at a resumable idle boundary preserves the allocation" do
    {session, wire} = start_session()
    update_handle(session, wire, "synthetic-idle-handle")
    TestGoogleSTSTransport.disconnect(wire)
    assert_receive {:test_google_sts_started, pending, _connection}
    assert_receive {:test_google_sts_control, ^pending, _setup}
    deliver_sync(session, pending, %{"setupComplete" => %{}})
    assert :ok = Session.push_audio(session, <<4, 0>>)
    assert_receive {:test_google_sts_audio, ^pending, <<4, 0>>}
  end

  test "accepted input invalidates a handle until a newer resumable checkpoint arrives" do
    {session, wire} = start_session()
    monitor = session |> Session.tree() |> Process.monitor()
    update_handle(session, wire, "synthetic-before-input")
    assert :ok = Session.push_audio(session, <<5, 0>>)
    TestGoogleSTSTransport.disconnect(wire)
    assert_receive {:DOWN, ^monitor, :process, _, _}
    refute_received {:test_google_sts_started, _, _}
  end

  test "a replacement that never acknowledges setup expires without a fresh-session fallback" do
    {session, wire} = start_session(resumption_timeout_ms: 50)
    monitor = session |> Session.tree() |> Process.monitor()
    update_handle(session, wire, "synthetic-timeout-handle")
    deliver(wire, %{"goAway" => %{"timeLeft" => "60s"}})
    assert_receive {:test_google_sts_started, pending, _connection}
    pending_monitor = Process.monitor(pending)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert_receive {:DOWN, ^pending_monitor, :process, ^pending, _reason}, 1_000
    refute_received {:test_google_sts_started, _, _}
  end

  test "renewal waits for playback settlement and sends no historical input or generated speech" do
    {session, wire} = start_session()
    output = finish_generation(session, wire)
    update_handle(session, wire, "synthetic-after-generation")
    deliver_sync(session, wire, %{"goAway" => %{"timeLeft" => "60s"}})
    refute_received {:test_google_sts_started, _, _}

    assert :ok = Session.settle_output(session, output, 20)
    assert_receive {:test_google_sts_started, pending, _connection}
    assert_receive {:test_google_sts_control, ^pending, setup}
    decoded = JSON.decode!(setup)
    assert Map.keys(decoded) == ["setup"]
    refute Map.has_key?(decoded, "clientContent")
    assert decoded["setup"]["sessionResumption"]["handle"] == "synthetic-after-generation"

    deliver_sync(session, pending, %{"setupComplete" => %{}})
    refute_received {:test_google_sts_control, ^pending, _}
    refute_received {:test_google_sts_audio, ^pending, _}
    refute_received {:vxpipe_speech_audio, %Audio{session: ^session}}
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended}}

    # Only genuinely new caller input goes onto the resumed connection.
    assert :ok = Session.push_audio(session, <<7, 0>>)
    assert_receive {:test_google_sts_audio, ^pending, <<7, 0>>}
    refute_received {:test_google_sts_audio, ^pending, _}
  end

  test "replacement setup failure never opens a fresh session" do
    {session, wire} = start_session()
    monitor = session |> Session.tree() |> Process.monitor()
    update_handle(session, wire, "synthetic-rejected-handle")
    deliver(wire, %{"goAway" => %{"timeLeft" => "60s"}})
    assert_receive {:test_google_sts_started, pending, _connection}
    assert_receive {:test_google_sts_control, ^pending, _setup}
    deliver(pending, %{"error" => %{"code" => 400}})
    assert_receive {:DOWN, ^monitor, :process, _, _}
    refute_received {:test_google_sts_started, _, _}
  end

  test "go-away allows playback to settle before the shorter reconnect budget begins" do
    {session, wire} = start_session(resumption_timeout_ms: 50)
    monitor = session |> Session.tree() |> Process.monitor()
    output = finish_generation(session, wire)
    update_handle(session, wire, "synthetic-pending-playback")
    deliver_sync(session, wire, %{"goAway" => %{"timeLeft" => "1s"}})
    refute_receive {:DOWN, ^monitor, :process, _, _}, 100

    assert :ok = Session.settle_output(session, output, 20)
    assert_receive {:test_google_sts_started, pending, _connection}
    assert_receive {:test_google_sts_control, ^pending, _setup}
    deliver_sync(session, pending, %{"setupComplete" => %{}})
    assert :ok = Session.push_audio(session, <<8, 0>>)
    assert_receive {:test_google_sts_audio, ^pending, <<8, 0>>}
    refute_received {:DOWN, ^monitor, :process, _, _}
  end

  test "google STS stays unadvertised until the hosted gate passes" do
    assert {:error, :unsupported_provider_capability} =
             Vxpipe.Providers.Registry.fetch_capability("google", :sts)

    selection = %Vxpipe.CallEngine.CallSpec.CapabilitySelection{
      kind: :speech_to_speech,
      provider: "google",
      model: "gemini-3.8-live",
      credential_name: nil,
      options: %{},
      provider_options: %{}
    }

    assert {:error, :unsupported_capability} =
             Vxpipe.CallEngine.CapabilityCatalog.validate(selection)
  end

  defp start_session(opts \\ []) do
    turn_control = Keyword.get(opts, :turn_control, "provider")

    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))

    {:ok, config} =
      STS.new(
        api_key: "synthetic-google-sts-key",
        model: "gemini-3.8-live",
        voice: "Kore",
        turn_control: turn_control
      )

    private =
      [
        config: config,
        wire_module: TestGoogleSTSTransport,
        wire_options: [observer: self()]
      ] ++ Keyword.take(opts, [:renew_after_ms, :expire_after_ms, :resumption_timeout_ms])

    {:ok, session, :starting} =
      Session.start(CapabilityTree.scope(scope),
        provider: STSSession,
        options: [model: "gemini-3.8-live", voice: "Kore", turn_control: turn_control],
        private: private,
        owner: self()
      )

    assert_receive {:test_google_sts_started, wire, _connection}, 5_000
    TestGoogleSTSTransport.deliver(wire, JSON.encode!(%{"setupComplete" => %{}}))

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}
    assert :ok = Session.ack(session, ready)
    {session, wire}
  end

  defp deliver(wire, message) do
    TestGoogleSTSTransport.deliver(wire, JSON.encode!(message))
  end

  defp deliver_sync(session, wire, message) do
    deliver(wire, message)
    _ = :sys.get_state(wire)
    _ = :sys.get_state(Session.provider(session))
    :ok
  end

  defp update_handle(session, wire, handle) do
    deliver_sync(session, wire, %{
      "sessionResumptionUpdate" => %{"newHandle" => handle, "resumable" => true}
    })
  end

  defp finish_generation(session, wire) do
    deliver(wire, %{"serverContent" => %{"activityStart" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started} = started}
    assert :ok = Session.ack(session, started)
    deliver(wire, %{"serverContent" => %{"turnComplete" => true}})
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended} = ended}
    assert :ok = Session.ack(session, ended)
    assert {:ok, output} = Session.admit_output(session, ended.turn_ref)

    deliver(wire, %{
      "serverContent" => %{
        "outputTranscription" => %{"text" => "reply before reconnect"},
        "modelTurn" => %{
          "parts" => [
            %{
              "inlineData" => %{
                "mimeType" => "audio/pcm;rate=24000",
                "data" => Base.encode64(:binary.copy(<<1, 0>>, 480))
              }
            }
          ]
        },
        "generationComplete" => true
      }
    })

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :output_transcript} = text}
    assert :ok = Session.ack(session, text)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = audio}
    assert :ok = Session.ack_audio(session, audio)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_completed} = completed}

    assert :ok = Session.ack(session, completed)
    output
  end

  defp drain_until_tool_response(wire, response) do
    if response =~ "toolResponse" do
      response
    else
      assert_receive {:test_google_sts_control, ^wire, next}, 5_000
      drain_until_tool_response(wire, next)
    end
  end
end
