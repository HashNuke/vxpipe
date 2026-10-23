defmodule Vxpipe.Gateway.HTTP.CallHangupsTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, TestMemoryRepository}
  alias Vxpipe.Gateway.HTTP.CallHangups
  alias Vxpipe.Identity.Principal
  @now ~U[2026-10-15 12:00:00Z]
  @platform "vxpk_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: {TestMemoryRepository, repository},
      call_spec_repository: {TestMemoryRepository, repository},
      call_repository: {TestMemoryRepository, repository},
      access_key_repository: {__MODULE__, nil},
      now: @now,
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("Token HTTP", [:calls], options)
    {:ok, actor} = Calls.authenticate_api_key(key.secret, options)
    {:ok, draft} = Calls.save_call_spec(tenant.key, source(), options)
    {:ok, published} = Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)

    {:ok, call} =
      Calls.claim_call(actor, tenant.key, published.call_spec_id, %{}, nil, nil, options)

    [participant] = Map.keys(call.participant_routes)

    browser = %Principal{
      user_public_id: "browser-user",
      session_public_id: "browser-session",
      account_kind: :member,
      grants: MapSet.new(["calls.write"]),
      assigned_tenants: %{tenant.key => :read_write},
      all_tenant_actions: MapSet.new()
    }

    %{
      options: options,
      tenant: tenant.key,
      call: call.id,
      participant: participant,
      key: key.secret,
      browser: browser
    }
  end

  test "canonical HTTP returns safe terminal status for tenant, platform and browser actors", c do
    for key <- [c.key, @platform, nil] do
      response = request(c, %{}, key)
      assert response.status == 200
      assert JSON.decode!(response.resp_body) == %{"call_id" => c.call, "status" => "ended"}
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end
  end

  test "browser response hooks survive downstream invalid input and explicit auth never falls back",
       c do
    response = request(c, %{"reason" => "private"}, nil)
    assert response.status == 400
    assert get_resp_header(response, "x-browser-hook") == ["retained"]
    assert_received :browser_authenticated
    response = request(c, %{}, "invalid")
    assert response.status == 401
    refute_received :browser_authenticated
    assert request(c, %{}, nil, browser_auth: {__MODULE__, :deny}).status == 403
  end

  test "invalid input, missing calls and denied scopes remain bounded", c do
    for body <- [%{"incarnation_id" => "override"}, %{"reason" => "override"}, [], nil] do
      assert request(c, body, c.key).status == 400
    end

    assert request(%{c | call: "missing"}, %{}, c.key).status == 404
    assert request(%{c | tenant: "BBBBBBBBBBBBBBBB"}, %{}, c.key).status == 403
    {:ok, admin} = Calls.issue_api_key(c.tenant, "admin", [:admin], c.options)
    assert request(c, %{}, admin.secret).status == 403
  end

  test "admission without verified runtime retains intent and reports unknown without retry advice",
       c do
    assert {:ok, token} = Calls.issue_call_join_token(c.browser, c.tenant, c.call, nil, c.options)

    assert {:ok, _} =
             Calls.claim_join_token(
               token.secret,
               %{tenant_key: c.tenant, call_id: c.call, participant_key: token.participant_key},
               c.options
             )

    response = request(c, %{}, c.key)
    assert response.status == 503

    assert %{
             "error" => %{"code" => "call_hangup_unknown", "retryable" => false, "details" => %{}}
           } = JSON.decode!(response.resp_body)

    assert {:ok, stored} = Calls.fetch_call(c.tenant, c.call, c.options)
    assert stored.state == :admitting and stored.hangup_requested_at == @now
    refute response.resp_body =~ token.secret
  end

  test "router forwards enablement and shared call options", c do
    for {enabled, status} <- [{false, 404}, {true, 200}] do
      options =
        Vxpipe.Gateway.HTTP.Endpoint.init(
          call_admission: [enabled: enabled, backend: {Vxpipe.Gateway.CallAdmission, c.options}]
        )

      response =
        conn(:post, "/api/tenants/#{c.tenant}/calls/#{c.call}/hangup", "{}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer " <> c.key)
        |> Vxpipe.Gateway.HTTP.Endpoint.call(options)

      assert response.status == status
    end
  end

  def authenticate_platform(_context, digest) do
    if digest == :crypto.hash(:sha256, @platform),
      do: {:ok, "platform"},
      else: {:error, :invalid_api_key}
  end

  def authenticate(conn, :deny), do: {:halt, conn |> send_resp(403, "csrf denied") |> halt()}

  def authenticate(conn, actor) do
    send(self(), :browser_authenticated)
    {:ok, register_before_send(conn, &put_resp_header(&1, "x-browser-hook", "retained")), actor}
  end

  defp request(c, body, key, overrides \\ []) do
    options =
      CallHangups.init(
        Keyword.merge(
          [enabled: true, calls_options: c.options, browser_auth: {__MODULE__, c.browser}],
          overrides
        )
      )

    conn = %{conn(:post, "/") | body_params: body}
    conn = if key, do: put_req_header(conn, "authorization", "Bearer " <> key), else: conn
    CallHangups.request(conn, options, c.tenant, c.call)
  end

  defp source do
    %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{type: "agent", prompt: "Help."}
      }
    }
  end
end
