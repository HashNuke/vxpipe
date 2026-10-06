defmodule Vxpipe.Console.Integration.LiveTelephonyTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias Vxpipe.Calls
  alias Vxpipe.Calls.TelephonyServices
  alias Vxpipe.CallEngine
  alias Vxpipe.Console.Test.ConfiguredTelephonyFixture
  alias Vxpipe.Console.Test.PublicTelephonyEndpoint

  alias Vxpipe.Console.Test.{
    LiveTelephonyPeer,
    LiveTelephonyPeerSocket,
    LiveTelephonyTransferModel
  }

  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.Telephony.MediaSupervisor

  alias Vxpipe.Persistence.{
    ArchiveStore,
    CallSpecStore,
    CallStore,
    CredentialKeyring,
    CredentialStore,
    InspectionStore,
    ProviderCredentialStore,
    Repo,
    TelephonyServiceStore,
    UsageStore
  }

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})
    private = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, private},
      telephony_service_repository: {TelephonyServiceStore, private},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      archive_repository: {ArchiveStore, Repo},
      inspection_repository: {InspectionStore, Repo},
      usage_repository: {UsageStore, Repo},
      registries: %{host_tools: %{}}
    ]

    %{options: options}
  end

  for {dialing, receiving, tag} <- [
        {"twilio", "telnyx", :live_telephony_twilio},
        {"telnyx", "twilio", :live_telephony_telnyx}
      ] do
    @dialing dialing
    @receiving receiving
    @tag :live_providers
    @tag :live_telephony
    @tag tag
    @tag timeout: 90_000
    test "#{dialing} to #{receiving} carries both remote greetings and closes both rooms",
         context do
      fixture = live_fixture(context)
      pair = ConfiguredTelephonyFixture.publish(fixture, @dialing, @receiving)

      try do
        outgoing = submit(fixture, pair.outgoing, pair.to)

        incoming =
          await("incoming room", 20_000, fn ->
            assert {:ok, page} = Calls.list_calls(fixture.principal, fixture.options)
            Enum.find(page.calls, &(&1.call_spec_id == pair.incoming.call_spec_id))
          end)

        assert {:ok, incoming} =
                 Calls.fetch_call(fixture.tenant.key, incoming.id, fixture.options)

        try do
          await("reciprocal remote audio transcripts", 25_000, fn ->
            remote_phrase?(fixture, outgoing, "bravo") and
              remote_phrase?(fixture, incoming, "alpha")
          end)
        rescue
          error in ExUnit.AssertionError ->
            diagnose_media(fixture, outgoing, "outgoing")
            diagnose_media(fixture, incoming, "incoming")
            reraise error, __STACKTRACE__
        end

        first_monitor = monitor_call(fixture, outgoing)
        second_monitor = monitor_call(fixture, incoming)

        stop_room(fixture.tenant.key, outgoing.room_id)
        assert_receive {:DOWN, ^first_monitor, :process, _room, _reason}, 5_000
        assert_receive {:DOWN, ^second_monitor, :process, _room, _reason}, 10_000

        await("durable closure of both calls", 10_000, fn ->
          ended?(fixture, outgoing.id) and ended?(fixture, incoming.id)
        end)

        assert {:ok, final} = Calls.fetch_call(fixture.tenant.key, outgoing.id, fixture.options)
        assert final.outgoing_outcome == :answered
        assert %DateTime{} = final.dial_submitted_at
        assert %DateTime{} = final.answered_at
        assert %DateTime{} = final.dial_ended_at

        IO.puts(
          "Live #{@dialing} -> #{@receiving}: signed carrier ingress; reciprocal remote phrases; both rooms ended; outgoing outcome answered"
        )

        IO.puts("Live webhook failure counts: #{inspect(webhook_failure_counts([]))}")
      after
        cleanup(fixture.tenant.key)
      end
    end
  end

  # One speech-to-speech provider over one carrier pair: GPT-Live answers on a real phone
  # leg, so carrier audio formats, line audio and opening timing meet a real STS model.
  @tag :live_providers
  @tag :live_telephony
  @tag :live_telephony_sts
  @tag timeout: 120_000
  test "GPT-Live handles a real carrier call in both directions of audio", context do
    System.get_env("OPENAI_API_KEY") ||
      flunk("set OPENAI_API_KEY in the live providers env file for the GPT-Live case")

    fixture = live_fixture(context)
    pair = ConfiguredTelephonyFixture.publish_sts(fixture, "twilio", "telnyx")

    try do
      outgoing = submit(fixture, pair.outgoing, pair.to)

      incoming =
        await("incoming room", 20_000, fn ->
          assert {:ok, page} = Calls.list_calls(fixture.principal, fixture.options)
          Enum.find(page.calls, &(&1.call_spec_id == pair.incoming.call_spec_id))
        end)

      assert {:ok, incoming} = Calls.fetch_call(fixture.tenant.key, incoming.id, fixture.options)

      try do
        await("GPT-Live opening heard on the phone", 25_000, fn ->
          remote_phrase?(fixture, incoming, "alpha")
        end)

        await("the callee heard by GPT-Live and its reply heard on the phone", 30_000, fn ->
          remote_phrase?(fixture, outgoing, "bravo") and
            remote_phrase?(fixture, incoming, "charlie")
        end)
      rescue
        error in ExUnit.AssertionError ->
          diagnose_media(fixture, outgoing, "outgoing GPT-Live")
          diagnose_media(fixture, incoming, "incoming")
          reraise error, __STACKTRACE__
      end

      first_monitor = monitor_call(fixture, outgoing)
      second_monitor = monitor_call(fixture, incoming)
      stop_room(fixture.tenant.key, outgoing.room_id)
      assert_receive {:DOWN, ^first_monitor, :process, _room, _reason}, 5_000
      assert_receive {:DOWN, ^second_monitor, :process, _room, _reason}, 10_000

      await("durable closure of both calls", 10_000, fn ->
        ended?(fixture, outgoing.id) and ended?(fixture, incoming.id)
      end)

      assert {:ok, final} = Calls.fetch_call(fixture.tenant.key, outgoing.id, fixture.options)
      assert final.outgoing_outcome == :answered

      IO.puts(
        "Live GPT-Live twilio -> telnyx: opening heard on the phone; callee heard by the model; model reply heard on the phone; both rooms ended"
      )
    after
      cleanup(fixture.tenant.key)
    end
  end

  @tag :live_providers
  @tag :live_telephony
  @tag :live_telephony_unanswered
  @tag timeout: 90_000
  test "an unrouteable cross-carrier dial ends within its five-second ring bound", context do
    fixture = live_fixture(context)

    pair =
      ConfiguredTelephonyFixture.publish(fixture, "twilio", "telnyx",
        answered?: false,
        ring_timeout_ms: 5_000
      )

    try do
      outgoing = submit(fixture, pair.outgoing, pair.to)

      final =
        await("bounded non-answer outcome", 10_000, fn ->
          assert {:ok, call} = Calls.fetch_call(fixture.tenant.key, outgoing.id, fixture.options)
          if call.state in [:ended, :failed], do: call
        end)

      assert final.outgoing_outcome in [:no_answer, :busy, :rejected, :failed, :unknown]
      assert is_nil(final.answered_at)
      assert %DateTime{} = final.dial_submitted_at
      assert %DateTime{} = final.dial_ended_at
      assert DateTime.diff(final.dial_ended_at, final.dial_submitted_at, :millisecond) <= 8_000
      assert {:ok, page} = Calls.list_calls(fixture.principal, fixture.options)
      assert length(page.calls) == 1

      IO.puts(
        "Live unanswered Twilio -> Telnyx: no published receiving route; one call; bounded outcome #{final.outgoing_outcome}; no answer timestamp"
      )
    after
      cleanup(fixture.tenant.key)
    end
  end

  @tag :live_providers
  @tag :live_telephony
  @tag :live_telephony_transfer
  @tag timeout: 120_000
  test "Twilio privately transfers with real destination press-1 and selective hangup", context do
    once = start_supervised!({Agent, fn -> false end})
    observer = self()

    destination_gate =
      start_supervised!(
        {Agent, fn -> %{open?: false, waiting: [], observer: observer} end},
        id: :destination_gate
      )

    start_supervised!({Registry, keys: :unique, name: LiveTelephonyPeerSocket.Registry})
    fixture = live_fixture(context, LiveTelephonyPeerSocket)
    configured = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.update!(
        configured,
        :agent_runtime,
        &Keyword.put(
          &1,
          :fixture,
          {LiveTelephonyTransferModel, once: once, destination_gate: destination_gate}
        )
      )
    )

    publications = ConfiguredTelephonyFixture.publish_transfer(fixture)

    try do
      caller = submit(fixture, publications.caller)
      reception = await_incoming_call(fixture, publications.reception)
      destination = await_incoming_call(fixture, publications.destination)
      destination_binding = await_peer_binding(fixture, destination, "human")
      support_binding = await_peer_binding(fixture, reception, "support")

      await("remote private briefing", 15_000, fn ->
        remote_phrase?(fixture, destination, "delta") or
          remote_phrase?(fixture, destination, "check")
      end)

      await("destination-only press-1 readiness", 15_000, fn ->
        match?(
          {:ok,
           %{transfer_acceptance_ready?: true, attachment: %{admission: :transfer_preparation}}},
          MediaSupervisor.snapshot(support_binding.client_state_leg_id)
        )
      end)

      refute remote_phrase?(fixture, caller, "delta")
      refute remote_phrase?(fixture, caller, "check")
      refute remote_phrase?(fixture, caller, "bravo")
      refute remote_phrase?(fixture, destination, "alpha")

      assert {:ok, destination} =
               Calls.fetch_call(fixture.tenant.key, destination.id, fixture.options)

      assert {:ok, peer} = LiveTelephonyPeer.new(fixture, destination, destination_binding)
      assert :ok = LiveTelephonyPeer.press_one(peer)

      assert_receive {:live_socket_result,
                      %{
                        provider: :twilio,
                        event: :dtmf,
                        result: :ok,
                        dtmf_track: track,
                        dtmf_press_one?: true
                      }},
                     5_000

      IO.puts("Real Twilio destination press-1 track: #{track}")

      await("accepted human bridge", 10_000, fn ->
        match?(
          {:ok, %{attachment: %{admission: :main}}},
          MediaSupervisor.snapshot(support_binding.client_state_leg_id)
        )
      end)

      assert :ok = LiveTelephonyTransferModel.open_destination(destination_gate)

      await("reciprocal speech across the human bridge", 20_000, fn ->
        remote_phrase?(fixture, caller, "bravo") and remote_phrase?(fixture, destination, "alpha")
      end)

      refute remote_phrase?(fixture, caller, "delta")
      refute remote_phrase?(fixture, caller, "check")
      assert_transfer_completed(fixture, reception)
      assert {:ok, page} = Calls.list_calls(fixture.principal, fixture.options)
      assert length(page.calls) == 3

      caller_monitor = monitor_call(fixture, caller)
      reception_monitor = monitor_call(fixture, reception)
      destination_monitor = monitor_call(fixture, destination)
      support_monitor = Process.monitor(support_binding.leg)
      assert {:ok, media} = MediaSupervisor.snapshot(support_binding.client_state_leg_id)
      media_monitor = Process.monitor(media.connection)

      assert :ok = LiveTelephonyPeer.hangup(peer)
      assert_receive {:DOWN, ^destination_monitor, :process, _, _}, 10_000
      assert_receive {:DOWN, ^support_monitor, :process, _, _}, 10_000
      assert_receive {:DOWN, ^media_monitor, :process, _, _}, 5_000
      caller_binding = await_peer_binding(fixture, reception, "human")

      assert {:ok, %{attachment: %{admission: :main}}} =
               MediaSupervisor.snapshot(caller_binding.client_state_leg_id)

      refute_receive {:DOWN, ^caller_monitor, :process, _, _}, 100
      refute_receive {:DOWN, ^reception_monitor, :process, _, _}, 100

      stop_room(fixture.tenant.key, reception.room_id)
      assert_receive {:DOWN, ^reception_monitor, :process, _, _}, 5_000
      assert_receive {:DOWN, ^caller_monitor, :process, _, _}, 10_000

      await("all three durable call/archive closures", 10_000, fn ->
        Enum.all?([caller, reception, destination], &ended?(fixture, &1.id))
      end)

      IO.puts(
        "Live Twilio transfer: remote private briefing; real destination press-1; reciprocal bridge speech; selective destination hangup; three archives closed"
      )
    rescue
      error in ExUnit.AssertionError ->
        assert {:ok, page} = Calls.list_calls(fixture.principal, fixture.options)

        Enum.each(page.calls, fn summary ->
          assert {:ok, call} = Calls.fetch_call(fixture.tenant.key, summary.id, fixture.options)
          diagnose_media(fixture, call, "transfer")
        end)

        reraise error, __STACKTRACE__
    after
      cleanup(fixture.tenant.key)
    end
  end

  defp await_incoming_call(fixture, publication) do
    incoming =
      await("published incoming transfer room", 20_000, fn ->
        assert {:ok, page} = Calls.list_calls(fixture.principal, fixture.options)
        Enum.find(page.calls, &(&1.call_spec_id == publication.call_spec_id))
      end)

    assert {:ok, call} = Calls.fetch_call(fixture.tenant.key, incoming.id, fixture.options)
    call
  end

  defp await_peer_binding(fixture, call, key) do
    participant = Map.fetch!(call.plan.participants, key)

    await("correlated carrier media binding", 5_000, fn ->
      case LiveTelephonyPeerSocket.binding(
             fixture.tenant.key,
             call.id,
             participant.participant_id
           ) do
        {:ok, binding} -> binding
        {:error, :peer_not_connected} -> nil
      end
    end)
  end

  defp assert_transfer_completed(fixture, call) do
    assert {:ok, facts} = Calls.fetch_call_facts(fixture.principal, call.id, fixture.options)

    started =
      Enum.filter(facts, &(&1.kind == :tool_call_started and &1.payload["name"] == "transfer"))

    assert length(started) == 1

    assert Enum.any?(
             facts,
             &(&1.kind == :tool_call_completed and
                 &1.payload["name"] == "transfer" and
                 &1.payload["result"]["status"] == "completed")
           )
  end

  test "encrypted carrier bindings publish opposing routes without dialing", context do
    fixture = ConfiguredTelephonyFixture.new(context.options, synthetic_settings())

    assert {:ok, telnyx} =
             TelephonyServices.resolve(fixture.tenant.key, "live-telnyx", fixture.options)

    assert telnyx.service.credential_owner == :platform
    assert telnyx.service.answering_machine_detection == :disabled

    assert {:ok, twilio} =
             TelephonyServices.resolve(fixture.tenant.key, "live-twilio", fixture.options)

    assert twilio.service.ingress_key == "vxp-test-twilio"
    assert twilio.service.answering_machine_detection == :disabled

    for {dialing, receiving} <- [{"twilio", "telnyx"}, {"telnyx", "twilio"}] do
      pair = ConfiguredTelephonyFixture.publish(fixture, dialing, receiving)
      assert pair.outgoing.source["outgoing_call"]["ring_timeout_ms"] == 15_000
      assert pair.incoming.source["incoming_call"]["caller"] == "human"

      assert {:ok, call} =
               Calls.claim_outgoing_call(
                 fixture.principal,
                 pair.outgoing.call_spec_id,
                 %{},
                 pair.to,
                 nil,
                 fixture.options
               )

      assert call.plan.direction == :outgoing
      human = Map.fetch!(call.plan.participants, call.plan.entry_caller)
      assert human.telephony_service.provider == dialing
      assert human.connection.number == Map.fetch!(fixture.settings.numbers, receiving)
      serialized = :erlang.term_to_binary(pair)
      refute String.contains?(serialized, "synthetic-private")
      assert call.state == :admitting
    end
  end

  test "assembled production endpoint keeps outgoing authentication before dialing", context do
    fixture = ConfiguredTelephonyFixture.new(context.options, synthetic_settings())
    pair = ConfiguredTelephonyFixture.publish(fixture, "twilio", "telnyx")

    endpoint =
      Vxpipe.Gateway.HTTP.Endpoint.init(ConfiguredTelephonyFixture.endpoint_options(fixture))

    health = Plug.Test.conn(:get, "/healthz") |> Vxpipe.Gateway.HTTP.Endpoint.call(endpoint)
    assert health.status == 200

    url =
      "/api/tenants/#{fixture.tenant.key}/call-specs/#{pair.outgoing.call_spec_id}/calls"

    response =
      Plug.Test.conn(:post, url, "{}")
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Vxpipe.Gateway.HTTP.Endpoint.call(endpoint)

    assert response.status == 401
    assert {:ok, page} = Calls.list_calls(fixture.principal, fixture.options)
    assert page.calls == []
  end

  test "published speech starts through encrypted resolution while dialing remains held",
       context do
    fixture = ConfiguredTelephonyFixture.new(context.options, synthetic_settings())
    pair = ConfiguredTelephonyFixture.publish(fixture, "twilio", "telnyx")

    assert {:ok, call} =
             Calls.claim_outgoing_call(
               fixture.principal,
               pair.outgoing.call_spec_id,
               %{},
               pair.to,
               nil,
               fixture.options
             )

    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    on_exit(fn -> cleanup(fixture.tenant.key) end)

    configured =
      ConfiguredTelephonyFixture.engine_settings(original,
        wire_module: Vxpipe.CallEngine.TestTextToSpeechTransport,
        wire_options: [observer: self(), ready_on_start: true]
      )

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, configured)

    assert {:ok, room} =
             CallEngine.start_call(call.plan,
               credential_source: {Vxpipe.Calls.ProviderCredentialSource, fixture.options},
               outbound_leg_connector:
                 {Vxpipe.CallEngine.TestOutboundLegConnector,
                  %{observer: self(), owner: self(), block?: true}}
             )

    assert_receive {:test_tts_transport_started, wire, connection}, 5_000
    assert connection.url =~ "api.deepgram.com/v2/speak"
    query = connection.url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["sample_rate"] == "48000"
    assert_receive {:test_outbound_leg_connect, _worker, _request, _timeout}, 1_000

    assert {:ok, monitor} =
             CallEngine.monitor_room(fixture.tenant.key, call.room_id, room.incarnation_id)

    refute_received {:test_tts_control, ^wire, _command}
    refute_received {:vxpipe_outgoing_submission, _token, _result}
    cleanup(fixture.tenant.key)
    assert_receive {:DOWN, ^monitor, :process, _room, _reason}, 5_000
  end

  test "production outgoing connector submits once through an encrypted carrier binding",
       context do
    settings = %{
      synthetic_settings()
      | auth_token: "observer:" <> List.to_string(:erlang.pid_to_list(self()))
    }

    fixture = ConfiguredTelephonyFixture.new(context.options, settings)
    pair = ConfiguredTelephonyFixture.publish(fixture, "twilio", "telnyx")
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    on_exit(fn -> cleanup(fixture.tenant.key) end)

    configured =
      ConfiguredTelephonyFixture.engine_settings(original,
        wire_module: Vxpipe.CallEngine.TestTextToSpeechTransport,
        wire_options: [observer: self(), ready_on_start: true]
      )

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, configured)

    endpoint =
      Endpoint.init(
        ConfiguredTelephonyFixture.endpoint_options(
          fixture,
          %{twilio: Vxpipe.Gateway.TestTwilioTelephonyAdapter}
        )
      )

    path =
      "/api/tenants/#{fixture.tenant.key}/call-specs/#{pair.outgoing.call_spec_id}/calls"

    response =
      Plug.Test.conn(:post, path, JSON.encode!(%{"to" => pair.to}))
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> fixture.key.secret)
      |> Endpoint.call(endpoint)

    assert response.status == 201
    assert_receive {:test_twilio_dial, request}, 1_000
    assert request.to == fixture.settings.numbers["telnyx"]
    assert request.from == fixture.settings.numbers["twilio"]
    assert request.answering_machine_detection == :disabled
    refute_received {:test_twilio_dial, _duplicate}
    cleanup(fixture.tenant.key)
    assert_receive {:test_twilio_end_leg, _ended}, 5_000
  end

  @tag :integration
  test "signed incoming Twilio admission starts the published encrypted call", context do
    assert_signed_incoming(context, "https://telephony.example.test", 0, nil)
  end

  @tag :live_providers
  @tag :live_telephony
  @tag :live_telephony_endpoint
  test "public Funnel admits a signed synthetic Twilio call without carrier dialing", context do
    public_url = System.fetch_env!("TELEPHONY_TEST_PUBLIC_URL")
    port = System.fetch_env!("TELEPHONY_TEST_PORT") |> String.to_integer()
    endpoints = PublicTelephonyEndpoint.resolve(public_url)
    assert_signed_incoming(context, public_url, port, endpoints)
  end

  defp assert_signed_incoming(context, public_url, listener_port, request_origin) do
    settings = %{
      synthetic_settings()
      | auth_token: "observer:" <> List.to_string(:erlang.pid_to_list(self()))
    }

    settings = %{settings | public_url: public_url}
    fixture = ConfiguredTelephonyFixture.new(context.options, settings)
    pair = ConfiguredTelephonyFixture.publish(fixture, "telnyx", "twilio")
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    on_exit(fn -> cleanup(fixture.tenant.key) end)

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      ConfiguredTelephonyFixture.engine_settings(original,
        wire_module: Vxpipe.CallEngine.TestTextToSpeechTransport,
        wire_options: [observer: self(), ready_on_start: true]
      )
    )

    endpoint_options =
      ConfiguredTelephonyFixture.endpoint_options(
        fixture,
        %{twilio: Vxpipe.Gateway.TestTwilioTelephonyAdapter}
      )

    server =
      start_supervised!(
        {Bandit,
         plug: {Endpoint, endpoint_options},
         ip: :loopback,
         port: listener_port,
         startup_log: false}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    path = "/api/telephony/twilio/vxp-test-twilio/voice"

    parameters = %{
      "AccountSid" => settings.account_sid,
      "CallSid" => "CA00000000000000000000000000000002",
      "CallStatus" => "ringing",
      "Direction" => "inbound",
      "From" => settings.numbers["telnyx"],
      "To" => settings.numbers["twilio"]
    }

    signed =
      parameters
      |> Enum.sort()
      |> Enum.reduce(
        settings.public_url <> path,
        fn {key, value}, input -> input <> key <> value end
      )

    signature = :crypto.mac(:hmac, :sha, settings.auth_token, signed) |> Base.encode64()

    options = [
      headers: [
        {"content-type", "application/x-www-form-urlencoded"},
        {"x-twilio-signature", signature}
      ],
      body: URI.encode_query(parameters),
      retry: false
    ]

    result =
      if request_origin do
        endpoint = await_public_endpoint(request_origin)
        PublicTelephonyEndpoint.request(endpoint, :post, path, options)
      else
        Req.post("http://127.0.0.1:#{port}" <> path, options)
      end

    assert {:ok, response} = result

    assert response.status == 200
    assert response.body =~ "<Connect><Stream"
    assert_receive {:test_twilio_answer, _request}, 1_000
    assert {:ok, page} = Calls.list_calls(fixture.principal, fixture.options)
    assert [%{id: call_id, call_spec_id: id, state: :admitting}] = page.calls
    assert id == pair.incoming.call_spec_id
    assert {:ok, call} = Calls.fetch_call(fixture.tenant.key, call_id, fixture.options)
    monitor = monitor_call(fixture, %{call | incarnation_id: nil})
    cleanup(fixture.tenant.key)
    assert_receive {:DOWN, ^monitor, :process, _room, _reason}, 5_000
    assert_receive {:test_twilio_end_leg, _request}, 5_000
  end

  defp monitor_call(fixture, call) do
    human = Map.fetch!(call.plan.participants, call.plan.entry_caller)

    assert {:ok, participant} =
             CallEngine.participant_snapshot(
               fixture.tenant.key,
               call.room_id,
               human.participant_id
             )

    assert {:ok, monitor} =
             CallEngine.monitor_room(fixture.tenant.key, call.room_id, participant.incarnation_id)

    monitor
  end

  defp live_fixture(context, media_socket \\ Vxpipe.Gateway.TestObservedTelephonySocket) do
    handler = make_ref()

    :ok =
      :telemetry.attach_many(
        handler,
        [
          [:vxpipe, :telephony, :command, :rejected],
          [:vxpipe, :telephony, :webhook, :failed],
          [:vxpipe, :call_engine, :transfer, :phase, :stop],
          Vxpipe.Gateway.Telemetry.request_stop_event(),
          [:vxpipe, :test, :telephony, :socket]
        ],
        &__MODULE__.observe_live_boundary/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    settings = %{
      public_url: System.fetch_env!("TELEPHONY_TEST_PUBLIC_URL"),
      application_id: System.fetch_env!("TELNYX_APP_ID"),
      account_sid: System.fetch_env!("TWILIO_ACCOUNT_SID"),
      auth_token: System.fetch_env!("TWILIO_AUTH_TOKEN"),
      telnyx_key: System.fetch_env!("TELNYX_API_KEY"),
      public_key: System.fetch_env!("TELNYX_PUBLIC_KEY"),
      gemini_key: System.fetch_env!("GEMINI_API_KEY"),
      deepgram_key: System.fetch_env!("DEEPGRAM_API_KEY"),
      openai_key: System.get_env("OPENAI_API_KEY"),
      numbers: %{
        "twilio" => System.fetch_env!("TWILIO_TEST_FROM"),
        "telnyx" => System.fetch_env!("TELNYX_TEST_FROM")
      }
    }

    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    configured = ConfiguredTelephonyFixture.engine_settings(original)

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, configured)
    fixture = ConfiguredTelephonyFixture.new(context.options, settings)
    on_exit(fn -> cleanup(fixture.tenant.key) end)
    port = System.fetch_env!("TELEPHONY_TEST_PORT") |> String.to_integer()

    endpoint_options =
      ConfiguredTelephonyFixture.endpoint_options(fixture)
      |> Keyword.update!(
        :telephony,
        &Keyword.merge(&1,
          twilio_media_socket: media_socket,
          media_socket: media_socket
        )
      )

    start_supervised!(
      {Bandit,
       plug:
         {Vxpipe.Gateway.TestObservedTelephonyEndpoint,
          [endpoint_options: endpoint_options, observer: self()]},
       ip: :loopback,
       port: port,
       startup_log: false}
    )

    # Probe public relay addresses rather than split DNS's private tailnet route.
    # Readiness retries never submit a carrier call; the dial POST never retries.
    endpoint = settings.public_url |> PublicTelephonyEndpoint.resolve() |> await_public_endpoint()
    %{fixture | settings: Map.put(settings, :endpoint, endpoint)}
  end

  defp submit(fixture, publication, to \\ nil) do
    path =
      "/api/tenants/#{fixture.tenant.key}/call-specs/#{publication.call_spec_id}/calls"

    assert {:ok, response} =
             PublicTelephonyEndpoint.request(fixture.settings.endpoint, :post, path,
               headers: [{"authorization", "Bearer " <> fixture.key.secret}],
               json: if(to, do: %{"to" => to}, else: %{}),
               retry: false,
               receive_timeout: 60_000
             )

    if response.status != 201 do
      rejection =
        receive do
          {:live_carrier_rejection, measurements, metadata} -> {measurements, metadata}
        after
          0 -> :no_provider_rejection_observed
        end

      assert {:ok, page} = Calls.list_calls(fixture.principal, fixture.options)

      outcomes =
        Enum.map(page.calls, fn call ->
          %{
            state: call.state,
            outgoing_outcome: call.outgoing_outcome,
            submitted?: not is_nil(call.dial_submitted_at)
          }
        end)

      flunk(
        "outgoing API returned #{response.status}; bounded rejection #{inspect(rejection)}; stored outcomes #{inspect(outcomes)}"
      )
    end

    id = response.body["call"]["id"]
    assert {:ok, call} = Calls.fetch_call(fixture.tenant.key, id, fixture.options)
    call
  end

  def observe_live_boundary(
        [:vxpipe, :telephony, :webhook, :failed],
        measurements,
        metadata,
        observer
      ) do
    send(observer, {:live_webhook_failure, measurements, metadata})
  end

  def observe_live_boundary(
        [:vxpipe, :call_engine, :transfer, :phase, :stop],
        measurements,
        metadata,
        observer
      ) do
    duration = System.convert_time_unit(measurements.duration, :native, :millisecond)
    send(observer, {:live_transfer_phase, Map.take(metadata, [:phase, :outcome]), duration})
  end

  def observe_live_boundary(
        [:vxpipe, :telephony, :command, :rejected],
        measurements,
        metadata,
        observer
      ) do
    send(
      observer,
      {:live_carrier_rejection, Map.take(measurements, [:http_status]),
       Map.take(metadata, [:provider, :operation, :error_code])}
    )
  end

  def observe_live_boundary(
        [:vxpipe, :test, :telephony, :socket],
        _measurements,
        metadata,
        observer
      ) do
    send(observer, {:live_socket_result, metadata})
  end

  def observe_live_boundary(_http_event, _measurements, metadata, observer) do
    send(observer, {:live_http_result, Map.take(metadata, [:operation, :outcome, :status])})
  end

  defp await_public_endpoint(endpoints) do
    Enum.with_index(endpoints, 1)
    |> Enum.each(fn {endpoint, index} ->
      result = PublicTelephonyEndpoint.request(endpoint, :get, "/healthz", receive_timeout: 3_000)

      diagnostic =
        case result do
          {:ok, response} ->
            %{http_status: response.status}

          {:error, %Req.TransportError{reason: reason}} when is_atom(reason) ->
            %{transport: reason}

          _other ->
            :unavailable
        end

      IO.puts("Public relay #{index} initial health: #{inspect(diagnostic)}")
    end)

    await("every public Funnel relay to serve health before dialing", 30_000, fn ->
      if PublicTelephonyEndpoint.ready?(endpoints), do: List.first(endpoints)
    end)
  end

  defp remote_phrase?(fixture, call, phrase) do
    human = Map.fetch!(call.plan.participants, call.plan.entry_caller)
    assert {:ok, facts} = Calls.fetch_call_facts(fixture.principal, call.id, fixture.options)

    Enum.any?(facts, fn fact ->
      text =
        Map.get(fact.payload, "text", "")
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/, " ")

      fact.kind == :participant_transcription_final and
        fact.participant_id == human.participant_id and
        String.contains?(" " <> text <> " ", " " <> phrase <> " ")
    end)
  end

  defp diagnose_media(fixture, call, direction) do
    assert {:ok, current} = Calls.fetch_call(fixture.tenant.key, call.id, fixture.options)
    assert {:ok, facts} = Calls.fetch_call_facts(fixture.principal, call.id, fixture.options)
    human = Map.fetch!(call.plan.participants, call.plan.entry_caller)

    joined? =
      match?(
        {:ok, _},
        CallEngine.participant_snapshot(
          fixture.tenant.key,
          call.room_id,
          human.participant_id
        )
      )

    remote_words =
      facts
      |> Enum.filter(
        &(&1.kind == :participant_transcription_final and
            &1.participant_id == human.participant_id)
      )
      |> Enum.flat_map(fn fact ->
        Map.get(fact.payload, "text", "") |> String.downcase() |> String.split(~r/[^a-z0-9]+/)
      end)
      |> MapSet.new()

    diagnostic = %{
      state: current.state,
      outgoing_outcome: current.outgoing_outcome,
      human_joined?: joined?,
      mixer: mixer_stats(current.incarnation_id),
      fact_counts: Enum.frequencies_by(facts, & &1.kind),
      heard_words:
        Map.new(
          ["private", "destination", "check", "alpha", "bravo", "delta"],
          fn word ->
            {word, MapSet.member?(remote_words, word)}
          end
        )
    }

    IO.puts("Live #{direction} bounded media evidence: #{inspect(diagnostic)}")
    IO.puts("Live webhook failures: #{inspect(webhook_failure_counts([]))}")
    IO.puts("Live HTTP boundary counts: #{inspect(http_boundary_counts([]))}")
    IO.puts("Live socket boundary counts: #{inspect(socket_boundary_counts([]))}")
    IO.puts("Live transfer phase evidence: #{inspect(transfer_phase_evidence([]))}")
  end

  defp mixer_stats(incarnation_id) when is_binary(incarnation_id) do
    case Vxpipe.CallEngine.RoomMixer.whereis(incarnation_id) do
      nil -> {:error, :closed}
      mixer -> Vxpipe.CallEngine.RoomMixer.stats(mixer)
    end
  end

  defp mixer_stats(_incarnation_id), do: {:error, :not_started}

  defp transfer_phase_evidence(results) do
    receive do
      {:live_transfer_phase, metadata, duration} ->
        transfer_phase_evidence([{metadata, duration} | results])
    after
      0 -> Enum.reverse(results)
    end
  end

  defp webhook_failure_counts(results) do
    receive do
      {:live_webhook_failure, measurements, metadata} ->
        webhook_failure_counts([{metadata, measurements} | results])
    after
      0 -> Enum.frequencies(results)
    end
  end

  defp http_boundary_counts(results) do
    receive do
      {:live_http_result, metadata} -> http_boundary_counts([metadata | results])
    after
      0 -> Enum.frequencies(results)
    end
  end

  defp socket_boundary_counts(results) do
    receive do
      {:live_socket_result, metadata} ->
        socket_boundary_counts([metadata | results])

      {:test_media_signature, variants} ->
        socket_boundary_counts([%{signature_variants: variants} | results])
    after
      0 -> Enum.frequencies(results)
    end
  end

  defp ended?(fixture, id) do
    assert {:ok, call} = Calls.fetch_call(fixture.tenant.key, id, fixture.options)
    assert {:ok, facts} = Calls.fetch_call_facts(fixture.principal, id, fixture.options)
    call.state == :ended and Enum.any?(facts, &(&1.kind == :archive_stream_closed))
  end

  defp await(label, timeout, operation),
    do: await_until(label, System.monotonic_time(:millisecond) + timeout, operation)

  defp await_until(label, deadline, operation) do
    case operation.() do
      value when value not in [nil, false] ->
        value

      _pending ->
        remaining = deadline - System.monotonic_time(:millisecond)

        assert remaining > 0,
               "live acceptance timed out waiting for #{label}; no automatic redial"

        reference = make_ref()
        Process.send_after(self(), {:live_telephony_poll, reference}, min(100, remaining))

        receive do
          {:live_telephony_poll, ^reference} -> await_until(label, deadline, operation)
        after
          remaining -> flunk("live acceptance timer expired for #{label}")
        end
    end
  end

  defp cleanup(tenant) do
    authorities =
      Registry.select(Vxpipe.CallEngine.RoomRegistry, [{{{tenant, :_}, :"$1", :_}, [], [:"$1"]}])

    Enum.each(authorities, &stop_authority/1)
  end

  defp stop_room(tenant, room) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {tenant, room}) do
      [{authority, _}] -> stop_authority(authority)
      [] -> :ok
    end
  end

  defp stop_authority(authority) do
    GenServer.stop(authority, :shutdown, 5_000)
  catch
    :exit, {:noproc, _call} -> :ok
  end

  defp synthetic_settings do
    %{
      public_url: "https://telephony.example.test",
      application_id: "synthetic-application",
      account_sid: "AC00000000000000000000000000000000",
      auth_token: "synthetic-private-token",
      telnyx_key: "synthetic-private-telnyx",
      public_key: Base.encode64(<<1::256>>),
      gemini_key: "synthetic-private-gemini",
      deepgram_key: "synthetic-private-deepgram",
      numbers: %{"twilio" => "+15550001001", "telnyx" => "+15550001002"}
    }
  end
end
