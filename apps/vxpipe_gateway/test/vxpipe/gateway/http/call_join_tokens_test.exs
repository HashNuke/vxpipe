defmodule Vxpipe.Gateway.HTTP.CallJoinTokensTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, TestMemoryRepository}
  alias Vxpipe.Gateway.HTTP.CallJoinTokens
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

  test "keys and browser sessions issue the same bounded participant token", c do
    for {key, body, ttl} <- [
          {c.key, %{}, 300},
          {@platform, %{"join_token_ttl_seconds" => 86_400}, 86_400},
          {nil, %{"participant_key" => c.participant, "join_token_ttl_seconds" => 600}, 600}
        ] do
      response = request(c, body, key)
      assert response.status == 201
      assert get_resp_header(response, "cache-control") == ["no-store"]

      assert %{
               "call_id" => call,
               "participant_key" => participant,
               "join_token" => %{"token" => token, "expires_at" => expires}
             } = JSON.decode!(response.resp_body)

      assert call == c.call
      assert participant == c.participant
      assert String.starts_with?(token, "vxj_")
      assert expires == DateTime.to_iso8601(DateTime.add(@now, ttl))
      refute response.resp_body =~ c.key
    end
  end

  test "canonical route forwards shared token configuration and respects enablement", c do
    for {enabled, expected_status} <- [{true, 201}, {false, 404}] do
      options =
        Vxpipe.Gateway.HTTP.Endpoint.init(
          call_admission: [enabled: enabled, backend: {Vxpipe.Gateway.CallAdmission, c.options}]
        )

      response =
        conn(:post, "/api/tenants/#{c.tenant}/calls/#{c.call}/join-tokens", JSON.encode!(%{}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer " <> c.key)
        |> Vxpipe.Gateway.HTTP.Endpoint.call(options)

      assert response.status == expected_status
    end
  end

  test "explicit participant route retains its input and response envelope", c do
    response = request(c, %{"join_token_ttl_seconds" => 900}, c.key, :explicit)
    assert response.status == 201

    assert %{
             "call_id" => call,
             "participant_key" => participant,
             "join_token" => %{"expires_at" => "2026-10-15T12:15:00Z"}
           } = JSON.decode!(response.resp_body)

    assert call == c.call
    assert participant == c.participant
  end

  test "an explicit bad key cannot fall back to a browser session and session halts survive", c do
    response = request(c, %{}, "invalid")
    assert response.status == 401
    refute_received :browser_authenticated

    denied = request(c, %{}, nil, :canonical, browser_auth: {__MODULE__, :deny})
    assert denied.status == 403
    assert denied.resp_body == "csrf denied"
    assert denied.halted

    assert request(c, %{}, nil, :canonical, browser_auth: nil).status == 401
  end

  test "typed bounded input and tenant authority are checked before token storage", c do
    for body <- [
          %{"join_token_ttl_seconds" => 299},
          %{"join_token_ttl_seconds" => 86_401},
          %{"join_token_ttl_seconds" => "300"},
          %{"join_token_ttl_seconds" => nil},
          %{"participant_key" => nil},
          %{"participant_key" => 1},
          %{"participant_key" => ""},
          %{"extra" => true}
        ] do
      assert request(c, body, c.key).status == 400
    end

    foreign = request(%{c | tenant: "BBBBBBBBBBBBBBBB"}, %{}, c.key)
    assert foreign.status == 403
    assert JSON.decode!(foreign.resp_body)["error"]["code"] == "not_authorized"

    reader = %{c.browser | grants: MapSet.new(["calls.read"])}
    assert request(%{c | browser: reader}, %{}, nil).status == 403
  end

  test "missing calls, invalid participants and storage failures have safe fixed errors", c do
    assert request(%{c | call: "missing"}, %{}, c.key).status == 404
    assert request(c, %{"participant_key" => "missing"}, c.key).status == 404

    for failure <- [:returned, :raised] do
      options = Keyword.put(c.options, :call_repository, {__MODULE__, failure})
      response = request(%{c | options: options}, %{}, c.key)
      assert response.status == 503
      assert JSON.decode!(response.resp_body)["error"]["code"] == "call_management_unavailable"
      refute response.resp_body =~ "private-storage-sentinel"
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
    {:ok, conn, actor}
  end

  def fetch_call(:returned, _tenant, _call), do: {:error, {:private, "private-storage-sentinel"}}
  def fetch_call(:raised, _tenant, _call), do: raise("private-storage-sentinel")

  defp request(c, body, key, style \\ :canonical, overrides \\ []) do
    options =
      CallJoinTokens.init(
        Keyword.merge(
          [
            enabled: true,
            backend: {Vxpipe.Gateway.CallAdmission, c.options},
            browser_auth: {__MODULE__, c.browser}
          ],
          overrides
        )
      )

    conn = %{conn(:post, "/") | body_params: body}
    conn = if key, do: put_req_header(conn, "authorization", "Bearer " <> key), else: conn

    case style do
      :canonical -> CallJoinTokens.issue(conn, options, c.tenant, c.call)
      :explicit -> CallJoinTokens.issue_explicit(conn, options, c.tenant, c.call, c.participant)
    end
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
