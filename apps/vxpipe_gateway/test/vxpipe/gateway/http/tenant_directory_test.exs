defmodule Vxpipe.Gateway.HTTP.TenantDirectoryTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Calls.Tenant
  alias Vxpipe.Gateway.HTTP.Endpoint

  @tenant "AAAAAAAAAAAAAAAA"
  @other "BBBBBBBBBBBBBBBB"
  @platform "vxpk_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  test "tenant and platform keys use shared directory scope and safe public projections" do
    for {secret, scope, tenants} <- [
          {"calls-key", {:keys, [@tenant]}, [tenant(@tenant)]},
          {"full-key", {:keys, [@tenant]}, [tenant(@tenant)]},
          {@platform, :all, [tenant(@tenant), tenant(@other)]}
        ] do
      response = request("/api/tenants", secret, tenants: tenants)
      assert response.status == 200
      assert_received {:search_tenants, ^scope, "", 25, 0}
      assert get_resp_header(response, "cache-control") == ["no-store"]

      assert JSON.decode!(response.resp_body) == %{
               "items" => Enum.map(tenants, &Map.take(public_tenant(&1), ["tenant_key", "name"])),
               "pagination" => %{
                 "page" => 1,
                 "page_size" => 25,
                 "total" => length(tenants),
                 "total_pages" => 1
               }
             }

      refute response.resp_body =~ "api_key"
      refute response.resp_body =~ "tenant_id"
    end
  end

  test "detail lookup conceals foreign and missing tenants alike" do
    response = request("/api/tenants/#{@tenant}", "calls-key")
    assert response.status == 200
    assert JSON.decode!(response.resp_body) == public_tenant(tenant(@tenant))
    assert_received {:tenant_candidates, {:keys, [@tenant]}, 1}

    foreign = request("/api/tenants/#{@other}", "calls-key")
    missing = request("/api/tenants/#{@tenant}", "calls-key", tenants: [])
    assert foreign.status == 404
    assert missing.status == 404
    assert foreign.resp_body == missing.resp_body
    refute_received {:tenant_candidates, {:keys, [@other]}, _}

    assert request("/api/tenants/#{@other}", @platform, tenants: [tenant(@other)]).status == 200
  end

  test "query bounds and pagination are validated before directory reads" do
    response =
      request("/api/tenants?q=%20Acme%20&page=2&page_size=2", @platform,
        tenants: [tenant(@other)],
        total: 3
      )

    assert response.status == 200
    assert_received {:search_tenants, :all, "Acme", 2, 2}
    assert JSON.decode!(response.resp_body)["pagination"]["total_pages"] == 2

    for query <- ["page=0", "page_size=51", "page_size=1.5", "q[]=x", "tenant_id=1", "api_key=x"] do
      assert request("/api/tenants?#{query}", "calls-key").status == 422
    end

    refute_received {:search_tenants, _, _, _, _}

    empty = request("/api/tenants", "calls-key", tenants: [])
    assert empty.status == 200
    assert JSON.decode!(empty.resp_body)["pagination"]["total_pages"] == 0

    out_of_range = request("/api/tenants?page=2", "calls-key", tenants: [])
    assert out_of_range.status == 422
    assert JSON.decode!(out_of_range.resp_body)["error"]["code"] == "page_out_of_range"
  end

  test "session adapter runs only when Authorization is absent" do
    principal = browser_principal()
    browser_auth = {__MODULE__, {self(), principal}}
    response = request("/api/tenants", nil, browser_auth: browser_auth)
    assert response.status == 200
    assert_received :browser_authenticated
    assert_received {:search_tenants, {:keys, [@tenant]}, "", 25, 0}

    for headers <- [
          [{"authorization", "Bearer invalid"}],
          [{"authorization", "Basic ignored"}],
          [{"authorization", "Bearer calls-key"}, {"authorization", "Bearer full-key"}]
        ] do
      response = request("/api/tenants", nil, browser_auth: browser_auth, headers: headers)
      assert response.status == 401
    end

    refute_received :browser_authenticated
    refute_received {:search_tenants, _, _, _, _}
  end

  test "browser response hooks survive query and tenant lookup failures" do
    browser_auth = {__MODULE__, {self(), browser_principal()}}

    for {path, status} <- [
          {"/api/tenants?page_size=invalid", 422},
          {"/api/tenants?page=0", 422},
          {"/api/tenants/#{@other}", 404}
        ] do
      response = request(path, nil, browser_auth: browser_auth)
      assert response.status == status
      assert get_resp_header(response, "x-browser-response") == ["preserved"]
    end
  end

  test "standalone requests require a valid key and storage failures return safe errors" do
    for secret <- [nil, "unknown", "revoked", "vxop_legacy"] do
      assert request("/api/tenants", secret).status == 401
    end

    assert request("/api/tenants", "unscoped").status == 403
    refute_received {:search_tenants, _, _, _, _}

    for failure <- [:unavailable, :throw] do
      unavailable = request("/api/tenants", "calls-key", failure: failure)
      assert unavailable.status == 503

      assert JSON.decode!(unavailable.resp_body) == %{
               "error" => %{"code" => "tenant_directory_unavailable"}
             }
    end

    assert request("/api/tenants", "calls-key", failure: :authentication_unavailable).status ==
             503

    assert request("/api/tenants", "calls-key", enabled: false).status == 404
  end

  test "mounted tenant routes preserve enabled configuration and authenticate requests" do
    options =
      Vxpipe.Gateway.HTTP.Mount.init(path_prefix: "/voice", tenant_directory: [enabled: true])

    response = conn(:get, "/voice/api/tenants") |> Vxpipe.Gateway.HTTP.Mount.call(options)
    assert response.status == 401
    assert response.halted
    assert response.script_name == ["voice"]
  end

  def authenticate(conn, {observer, principal}) do
    send(observer, :browser_authenticated)
    conn = register_before_send(conn, &put_resp_header(&1, "x-browser-response", "preserved"))
    {:ok, conn, principal}
  end

  def fetch_api_key_by_digest(%{failure: :authentication_unavailable}, _digest),
    do: {:error, :repository_unavailable}

  def fetch_api_key_by_digest(_context, digest) do
    case Enum.find(
           ["calls-key", "full-key", "revoked", "unscoped"],
           &(:crypto.hash(:sha256, &1) == digest)
         ) do
      nil ->
        {:error, :not_found}

      secret ->
        scopes =
          case secret do
            "full-key" -> [:admin, :calls]
            "unscoped" -> []
            _ -> [:calls]
          end

        {:ok,
         %{
           id: "synthetic-key",
           tenant_key: @tenant,
           scopes: MapSet.new(scopes),
           revoked_at: if(secret == "revoked", do: ~U[2026-10-15 00:00:00Z])
         }}
    end
  end

  def authenticate_platform(_context, digest) do
    if digest == :crypto.hash(:sha256, @platform),
      do: {:ok, "synthetic-platform-key"},
      else: {:error, :invalid_api_key}
  end

  def search_tenants(context, scope, query, limit, offset) do
    send(context.observer, {:search_tenants, scope, query, limit, offset})
    if context.failure == :throw, do: throw(:private_repository_details)

    if context.failure == :unavailable,
      do: {:error, :repository_unavailable},
      else: {:ok, {context.tenants, context.total}}
  end

  def tenant_candidates(context, scope, limit) do
    send(context.observer, {:tenant_candidates, scope, limit})
    {:ok, context.tenants}
  end

  defp request(path, secret, options \\ []) do
    tenants = Keyword.get(options, :tenants, [tenant(@tenant)])

    context = %{
      observer: self(),
      tenants: tenants,
      total: Keyword.get(options, :total, length(tenants)),
      failure: Keyword.get(options, :failure)
    }

    endpoint =
      Endpoint.init(
        tenant_directory: [
          enabled: Keyword.get(options, :enabled, true),
          browser_auth: Keyword.get(options, :browser_auth),
          calls_options: [
            credential_repository: {__MODULE__, context},
            access_key_repository: {__MODULE__, context},
            admin_repository: {__MODULE__, context}
          ]
        ]
      )

    conn = conn(:get, path)

    headers =
      Keyword.get(
        options,
        :headers,
        if(secret, do: [{"authorization", "Bearer " <> secret}], else: [])
      )

    Endpoint.call(%{conn | req_headers: headers}, endpoint)
  end

  defp tenant(key), do: %Tenant{key: key, name: "Acme", inserted_at: ~U[2026-10-15 00:00:00Z]}

  defp public_tenant(tenant),
    do: %{
      "tenant_key" => tenant.key,
      "name" => tenant.name,
      "created_at" => DateTime.to_iso8601(tenant.inserted_at)
    }

  defp browser_principal do
    %Vxpipe.Identity.Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(["calls.read"]),
      assigned_tenants: %{@tenant => :read},
      all_tenant_actions: MapSet.new()
    }
  end
end
