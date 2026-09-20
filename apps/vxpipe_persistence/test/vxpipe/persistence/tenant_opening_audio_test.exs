defmodule Vxpipe.Persistence.TenantOpeningAudioTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.OpeningAudio.AssetCache
  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxTextToSpeech}

  alias Vxpipe.CallEngine.{
    RoomAuthority,
    TestAudioOutputSink,
    TestCallStartup,
    TestSpeechToTextTransport,
    TestTextToSpeechTransport,
    TestTransferConnection
  }

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, ProviderCredentials}
  alias Vxpipe.Persistence.{CallStore, CredentialKeyring, CredentialStore, CallSpecStore}
  alias Vxpipe.Persistence.ProviderCredentialStore
  alias Vxpipe.Persistence.Schema.{CallSpec, CallSpecRevision, ParticipantRoute}

  @moduletag capture_log: true

  setup do
    {:ok, keyring} =
      CredentialKeyring.new("opening-key", %{"opening-key" => :crypto.strong_rand_bytes(32)})

    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, issued} = Administration.bootstrap_tenant("Tenant opening", [:calls], options)
    {:ok, principal} = Administration.authenticate(tenant.key, issued.secret, :calls, options)
    context = %{tenant: tenant, principal: principal, options: options}
    provision(context, "default")
    configure_transports()
    before = room_supervisors()

    on_exit(fn ->
      for supervisor <- MapSet.difference(room_supervisors(), before) do
        DynamicSupervisor.terminate_child(CallEngine.RoomSupervisor, supervisor)
      end
    end)

    context
  end

  test "a healthy entry credential cannot replace the separate opening credential", ctx do
    before = row_counts()

    assert {:error, error} = Calls.save_call_spec(ctx.tenant.key, source(), ctx.options)
    assert error.code == :provider_credential_unavailable
    assert error.details == %{"path" => ["opening_audio", "text_to_speech"]}
    assert row_counts() == before

    provision(ctx, "opening")
    assert {:ok, draft} = Calls.save_call_spec(ctx.tenant.key, source(), ctx.options)
    assert draft.validation_errors == []
  end

  test "a human-entry call plays its tenant opening voice and retains independent caller speech",
       ctx do
    provision(ctx, "opening")
    plan = prepare(ctx)
    assert Enum.all?(plan.participants, fn {_ref, participant} -> participant.kind == :human end)
    refute :erlang.term_to_binary(plan) =~ "opening-private-marker"

    {room, tts} = start_room(ctx, plan, "opening")
    tts_monitor = Process.monitor(tts)
    sink = attach(plan, room)
    assert_receive {:test_stt_transport_started, _stt, stt_connection}, 1_000
    assert stt_connection.headers == [{"Authorization", "Token default-opening-private-marker"}]
    assert RoomAuthority.input_admission(plan.tenant_id, plan.room_id) == :opening_audio
    assert_synthesis(tts)
    render(tts, sink)
    assert RoomAuthority.input_admission(plan.tenant_id, plan.room_id) == :opening_audio
    assert :ok = TestAudioOutputSink.playback_started(sink)
    assert :ok = TestAudioOutputSink.playback_completed(sink)
    TestCallStartup.await_ready(plan.room_id)
    assert RoomAuthority.input_admission(plan.tenant_id, plan.room_id) == :open
    assert_receive {:DOWN, ^tts_monitor, :process, ^tts, _reason}, 1_000
    refute_receive {:test_agent_runtime_stream, _provider, _request}
  end

  test "cached text is reused only for the same tenant opening binding", ctx do
    provision(ctx, "opening")
    provision(ctx, "another-opening")

    {:ok, other, issued} =
      Administration.bootstrap_tenant(
        "Another opening tenant",
        [:calls],
        Keyword.put(ctx.options, :tenant_key_generator, fn -> "_234567890123456" end)
      )

    {:ok, principal} = Administration.authenticate(other.key, issued.secret, :calls, ctx.options)
    other_ctx = %{ctx | tenant: other, principal: principal}
    provision(other_ctx, "default")
    provision(other_ctx, "opening")

    for {selected, name, cached?} <- [
          {ctx, "opening", false},
          {ctx, "opening", true},
          {ctx, "another-opening", false},
          {other_ctx, "opening", false}
        ] do
      plan = prepare(selected, name)
      {room, tts} = start_room(selected, plan, name)
      sink = attach(plan, room)

      if cached? do
        assert_receive {:test_audio_output, ^sink, frame}, 1_000
        assert frame.payload == <<1, 0, 2, 0, 3, 0, 4, 0>>
        assert frame.audio_scope == :private
        assert_receive {:test_audio_output_finish, ^sink, _turn}, 1_000
        refute_receive {:test_tts_control, ^tts, _payload}
      else
        assert_synthesis(tts)
        render(tts, sink)
      end

      assert :ok = TestAudioOutputSink.playback_started(sink)
      assert :ok = TestAudioOutputSink.playback_completed(sink)
      TestCallStartup.await_ready(plan.room_id)
    end
  end

  test "a cached opening cannot rescue its revoked tenant credential on a new activation", ctx do
    credential = provision(ctx, "opening")
    first = prepare(ctx)
    {room, tts} = start_room(ctx, first, "opening")
    sink = attach(first, room)
    assert_synthesis(tts)
    render(tts, sink)
    assert :ok = TestAudioOutputSink.playback_started(sink)
    assert :ok = TestAudioOutputSink.playback_completed(sink)
    TestCallStartup.await_ready(first.room_id)

    plan = prepare(ctx)
    source = {Vxpipe.Persistence.TestControlledCredentialSource, {ctx.options, self(), "opening"}}
    assert {:ok, attempt} = CallEngine.start_call(plan, credential_source: source)
    assert_receive {:tenant_credential_pending, resolver, "deepgram", "opening"}, 1_000

    assert {:ok, monitor} =
             CallEngine.monitor_room(plan.tenant_id, plan.room_id, attempt.incarnation_id)

    assert {1, _} =
             Repo.update_all(
               from(c in Vxpipe.Persistence.Schema.ProviderCredential,
                 where: c.public_id == ^credential.id
               ),
               set: [status: "revoked"]
             )

    assert {:ok, _active} =
             ProviderCredentials.resolve(ctx.tenant.key, "deepgram", "default", ctx.options)

    send(resolver, :resolve)
    assert_receive {:DOWN, ^monitor, :process, _room, :opening_audio_unavailable}, 1_000
    refute_receive {:test_tts_transport_started, _tts, _connection}
    room_id = plan.room_id
    refute_receive {:test_call_ready, ^room_id}
    refute_receive {:test_audio_output, _sink, _frame}
  end

  defp provision(ctx, name) do
    assert {:ok, credential} =
             ProviderCredentials.provision(
               ctx.tenant.key,
               "deepgram",
               name,
               "api_key",
               %{"api_key" => name <> "-opening-private-marker"},
               ctx.options
             )

    credential
  end

  defp prepare(ctx, name \\ "opening") do
    assert {:ok, draft} = Calls.save_call_spec(ctx.tenant.key, source(name), ctx.options)
    assert draft.validation_errors == []

    assert {:ok, published} =
             Calls.publish_call_spec(ctx.tenant.key, draft.call_spec_id, 1, ctx.options)

    route = Enum.find(published.routes, &(&1.participant_ref == "caller"))
    assert {:ok, call, token} = Calls.prepare_call(ctx.principal, route.key, %{}, ctx.options)

    assert {:ok, claim} =
             Calls.claim_join_token(
               token.secret,
               %{tenant_key: ctx.tenant.key, call_id: call.id, participant_key: route.key},
               ctx.options
             )

    claim.call.plan
  end

  defp start_room(ctx, plan, name) do
    assert {:ok, room} =
             TestCallStartup.start_call(plan,
               credential_source: {Vxpipe.Calls.ProviderCredentialSource, ctx.options}
             )

    assert_receive {:test_tts_transport_started, tts, connection}, 1_000

    assert connection.headers == [
             {"Authorization", "Token " <> name <> "-opening-private-marker"}
           ]

    assert URI.decode_query(URI.parse(connection.url).query)["model"] == "flux-opening-voice"
    {room, tts}
  end

  defp attach(plan, room) do
    sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: {:sink, plan.call_id})

    for ref <- ["receiver", "caller"] do
      participant = Map.fetch!(plan.participants, ref)

      assert {:ok, command} =
               AttachConnection.new(
                 tenant_id: plan.tenant_id,
                 actor_id: plan.actor_id,
                 room_id: plan.room_id,
                 incarnation_id: room.incarnation_id,
                 participant_id: participant.participant_id,
                 connection_id: plan.call_id <> "-" <> ref,
                 deadline: DateTime.add(DateTime.utc_now(), 10, :second)
               )

      output = if ref == "caller", do: sink
      assert {:ok, _attachment} = TestTransferConnection.attach(command, output)
    end

    sink
  end

  defp assert_synthesis(tts) do
    assert_receive {:test_tts_control, ^tts, speak}, 1_000
    assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "A separate tenant opening."}
    assert_receive {:test_tts_control, ^tts, flush}, 1_000
    assert JSON.decode!(flush) == %{"type" => "Flush"}
  end

  defp render(tts, sink) do
    TestTextToSpeechTransport.deliver_control(
      tts,
      ~s({"type":"SpeechStarted","request_id":"opening","speech_id":"opening"})
    )

    for pcm <- [<<1, 0, 2, 0>>, <<3, 0, 4, 0>>] do
      reference = TestTextToSpeechTransport.deliver_audio_with_result(tts, pcm)
      assert_receive {:test_audio_output, ^sink, frame}, 1_000
      assert frame.payload == pcm
      assert frame.audio_scope == :private
      assert_receive {:test_tts_audio_result, ^reference, :ok}, 1_000
    end

    TestTextToSpeechTransport.deliver_control(
      tts,
      ~s({"type":"SpeechMetadata","request_id":"opening","speech_id":"opening"})
    )

    assert_receive {:test_audio_output_finish, ^sink, _turn}, 1_000
  end

  defp configure_transports do
    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)
    cache = start_supervised!({AssetCache, maximum_entries: 8, maximum_bytes: 1_048_576})

    settings =
      original
      |> Keyword.update!(:opening_audio, &Keyword.put(&1, :cache, cache))
      |> Keyword.put(:speech_to_text,
        providers: %{
          Flux.Session => [
            enabled: true,
            wire_module: TestSpeechToTextTransport,
            wire_options: [observer: self(), ready_on_start: true],
            media_ingress: [
              maximum_frames: 8,
              maximum_bytes: 1_024,
              maximum_age_ms: 1_000,
              maximum_consecutive_overflows: 2
            ]
          ]
        }
      )
      |> Keyword.put(:text_to_speech,
        providers: %{
          FluxTextToSpeech.Session => [
            enabled: true,
            wire_module: TestTextToSpeechTransport,
            wire_options: [observer: self(), ready_on_start: true],
            maximum_requests: 2
          ]
        }
      )

    Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings)
    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, original) end)
  end

  defp row_counts,
    do:
      Enum.map(
        [CallSpec, CallSpecRevision, ParticipantRoute],
        &Repo.aggregate(&1, :count)
      )

  defp room_supervisors do
    CallEngine.RoomSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
    |> MapSet.new()
  end

  defp source(name \\ "opening") do
    %{
      schema_version: "20260915.01",
      entry_caller: "caller",
      entry_receiver: "receiver",
      wait_sounds: nil,
      defaults: %{capabilities: %{}},
      opening_audio: %{
        type: "text",
        text: "A separate tenant opening.",
        text_to_speech: %{
          provider: "deepgram",
          model: "flux-opening-voice",
          credential_name: name,
          options: %{encoding: "linear16", sample_rate: 48_000}
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{
            speech_to_text: %{
              provider: "deepgram",
              model: "flux-general-en",
              options: %{encoding: "opus", sample_rate: 48_000}
            }
          }
        },
        "receiver" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        }
      }
    }
  end
end
