defmodule Vxpipe.Console.Integration.ManagedWebHangupTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias Vxpipe.{CallEngine, Calls}
  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Gateway.{CallAdmission, CallCleanup, CallCleanupRecovery, CallCleanupSupervisor}
  alias Vxpipe.Gateway.HTTP.Mount
  alias Vxpipe.Gateway.TestManagedWebPeer

  alias Vxpipe.Persistence.{
    AccessKeyStore,
    ArchiveStore,
    CallSpecStore,
    CallStore,
    CredentialStore,
    Repo
  }

  @moduletag :integration
  @moduletag capture_log: true

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    sandbox = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    mount = Endpoint.config(:gateway_mount)

    on_exit(fn ->
      Phoenix.Config.put(Endpoint, :gateway_mount, mount)
      Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox)
    end)

    options = [
      credential_repository: {CredentialStore, Repo},
      access_key_repository: {AccessKeyStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      archive_repository: {ArchiveStore, Repo},
      registries: %{host_tools: %{}},
      publication_enabled: false
    ]

    archive = [
      enabled: true,
      writer: {Vxpipe.Persistence.EctoStorage, options},
      maximum_pending_facts: 256,
      retry_delay_ms: 25,
      drain_timeout_ms: 5_000,
      source_policy: %{"revision" => 0}
    ]

    configured = Keyword.merge(options, managed_cleanup: true, archive: archive)

    Phoenix.Config.put(
      Endpoint,
      :gateway_mount,
      Mount.init(call_admission: [enabled: true, backend: {CallAdmission, configured}])
    )

    {:ok, tenant, key} = Calls.bootstrap_tenant("Local managed web acceptance", [:calls], options)
    {:ok, draft} = Calls.save_call_spec(tenant.key, source(), options)

    {:ok, published} =
      Calls.publish_call_spec(tenant.key, draft.call_spec_id, draft.revision, options)

    %{tenant: tenant.key, secret: key.secret, spec: published.call_spec_id, options: configured}
  end

  test "persisted web admission and connected WebRTC finish through authorized durable hangup",
       c do
    active = start_call(c)
    connect(active.session_id)
    assert {:ok, snapshot} = CallCleanup.observe(active.tracker)

    [{root, _}] =
      Enum.filter(snapshot.resources, fn {_pid, resource} -> resource.kind == :web_rtc end)

    root_monitor = Process.monitor(root)
    tracker_monitor = Process.monitor(active.tracker)
    session_monitor = Process.monitor(active.session)

    response = request(c.secret, :post, active.base <> "/hangup", %{})
    assert %{"call_id" => id, "status" => status} = json_response(response, 200)
    assert id == active.call.id and status in ["ending", "ended"]
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert_receive {:DOWN, ^root_monitor, :process, ^root, :shutdown}, 5_000
    assert_receive {:DOWN, ^session_monitor, :process, _, :normal}, 5_000
    assert_receive {:DOWN, ^tracker_monitor, :process, _, :normal}, 5_000

    assert {:ok, stored} = Calls.fetch_call(c.tenant, id, c.options)
    assert stored.state == :ended
    assert stored.terminal_reason == :api_hangup
    assert stored.incarnation_id == active.call.incarnation_id
    assert stored.gateway_cleanup_completed_at == stored.ended_at
    assert %DateTime{} = stored.hangup_requested_at
    assert DateTime.compare(stored.ended_at, stored.started_at) != :lt
    assert {:ok, facts} = ArchiveStore.fetch_call_facts(Repo, c.tenant, id)
    assert Enum.any?(facts, &(&1.kind == :archive_stream_closed))
    assert {:error, :not_found} = Vxpipe.Gateway.Session.claim(active.session_id)
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(active.binding)

    assert json_response(request(c.secret, :post, active.base <> "/hangup", %{}), 200) ==
             %{"call_id" => id, "status" => "ended"}

    assert request(c.secret, :post, active.base <> "/join-tokens", %{}).status == 409
    refute response.resp_body =~ "cleanup"
  end

  test "lost cleanup ownership remains durably unknown after exact shutdown and recovery", c do
    active = start_call(c)

    assert {:ok, room_monitor} =
             CallEngine.monitor_room_completion(
               c.tenant,
               active.call.room_id,
               active.call.incarnation_id
             )

    tracker_monitor = Process.monitor(active.tracker)
    session_monitor = Process.monitor(active.session)
    :ok = DynamicSupervisor.terminate_child(CallCleanupSupervisor, active.tracker)
    assert_receive {:DOWN, ^tracker_monitor, :process, _, :shutdown}, 5_000
    assert_receive {:DOWN, ^session_monitor, :process, _, :normal}, 5_000

    assert %{"error" => %{"code" => "call_hangup_unknown"}} =
             request(c.secret, :post, active.base <> "/hangup", %{}) |> json_response(503)

    assert_receive {:DOWN, ^room_monitor, :process, _, _}, 5_000
    assert {:ok, unresolved} = Calls.fetch_call(c.tenant, active.call.id, c.options)
    assert %DateTime{} = unresolved.hangup_requested_at
    assert unresolved.gateway_cleanup_completed_at == nil
    assert unresolved.state != :ended

    row =
      unresolved
      |> Map.take([
        :tenant_key,
        :room_id,
        :incarnation_id,
        :incarnation_binding_verified,
        :hangup_requested_at,
        :gateway_cleanup_required,
        :gateway_cleanup_completed_at
      ])
      |> Map.put(:call_id, unresolved.id)

    _ = CallCleanupRecovery.reconcile(row, c.options)
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(active.binding)
    assert {:ok, after_recovery} = Calls.fetch_call(c.tenant, unresolved.id, c.options)
    assert after_recovery.gateway_cleanup_completed_at == nil
    assert after_recovery.state != :ended
    assert after_recovery.hangup_requested_at == unresolved.hangup_requested_at
  end

  defp start_call(c) do
    created =
      request(c.secret, :post, "/api/tenants/#{c.tenant}/call-specs/#{c.spec}/calls", %{})
      |> json_response(201)

    id = created["call"]["id"]
    base = "/api/tenants/#{c.tenant}/calls/#{id}"
    token = request(c.secret, :post, base <> "/join-tokens", %{}) |> json_response(201)

    admitted =
      request(
        token["join_token"]["token"],
        :post,
        base <> "/participants/#{token["participant_key"]}/sessions",
        %{}
      )
      |> json_response(201)

    session_id = admitted["session"]["session_id"]
    [{session, _}] = Registry.lookup(Vxpipe.Gateway.SessionRegistry, session_id)
    {:ok, call} = Calls.fetch_call(c.tenant, id, c.options)
    assert call.state == :running and call.gateway_cleanup_required

    binding = %{
      tenant_key: c.tenant,
      call_id: id,
      room_id: call.room_id,
      incarnation_id: call.incarnation_id
    }

    assert {:ok, tracker} = CallCleanupSupervisor.lookup(binding)
    assert %{resources: %{^session => %{kind: :session}}} = CallCleanup.snapshot(tracker)

    on_exit(fn ->
      CallEngine.end_call(c.tenant, call.room_id, call.incarnation_id)

      case CallCleanupSupervisor.lookup(binding) do
        {:ok, owner} -> DynamicSupervisor.terminate_child(CallCleanupSupervisor, owner)
        _ -> :ok
      end
    end)

    %{
      call: call,
      base: base,
      session: session,
      session_id: session_id,
      tracker: tracker,
      binding: binding
    }
  end

  defp connect(session_id) do
    peer = start_supervised!({TestManagedWebPeer, []})
    offer = TestManagedWebPeer.offer(peer)

    answer =
      request(nil, :post, "/api/rtvi/offer", %{
        sdp: offer,
        type: "offer",
        pc_id: nil,
        restart_pc: false,
        requestData: %{session_id: session_id}
      })
      |> json_response(200)

    :ok = TestManagedWebPeer.answer(peer, answer["sdp"])
    assert_receive {:ex_webrtc, ^peer, {:ice_candidate, candidate}}, 5_000

    response =
      request(nil, :patch, "/api/rtvi/offer", %{
        pc_id: answer["pc_id"],
        candidates: [TestManagedWebPeer.candidate(candidate)]
      })

    assert response.status == 200
    assert_receive {:ex_webrtc, ^peer, {:connection_state_change, :connected}}, 5_000
    peer
  end

  defp request(secret, method, path, body) do
    conn = build_conn() |> put_req_header("content-type", "application/json")
    conn = if secret, do: put_req_header(conn, "authorization", "Bearer " <> secret), else: conn
    dispatch(conn, Endpoint, method, "https://localhost" <> path, JSON.encode!(body))
  end

  defp source do
    %{
      "schema_version" => "20261004.01",
      "defaults" => %{"capabilities" => %{}},
      "incoming_call" => %{"caller" => "caller", "handled_by" => "listener"},
      "participants" =>
        Map.new(["caller", "listener"], fn name ->
          {name,
           %{
             "type" => "human",
             "connection" => %{
               "service" => "web",
               "mode" => "receive",
               "admission" => "start_call"
             }
           }}
        end)
    }
  end
end
