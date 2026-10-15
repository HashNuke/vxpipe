defmodule Vxpipe.Gateway.HTTP.CallSpecReadsTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Calls.{CallSpecRevision, CallSpecSummary, Tenant}
  alias Vxpipe.Gateway.HTTP.Endpoint

  @tenant "AAAAAAAAAAAAAAAA"
  @other "BBBBBBBBBBBBBBBB"
  @path "/api/tenants/#{@tenant}/call-specs"
  @platform "vxpk_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  test "full tenant and platform keys receive rich bounded summaries" do
    for secret <- ["full-key", @platform] do
      response = request(@path <> "?page=2&page_size=2", secret)
      assert response.status == 200
      assert_received {:list_call_specs, @tenant, 2, 2}
      assert get_resp_header(response, "cache-control") == ["no-store"]

      assert JSON.decode!(response.resp_body) == %{
               "tenant" => %{"key" => @tenant, "name" => "Example"},
               "call_specs" => [
                 %{
                   "id" => "example",
                   "name" => "Example spec",
                   "latest_revision" => 3,
                   "published_revision" => 2,
                   "call_count" => 4,
                   "updated_at" => "2026-10-15T00:00:00Z"
                 }
               ],
               "pagination" => %{"page" => 2, "page_size" => 2, "total" => 3, "total_pages" => 2}
             }
    end
  end

  test "detail preserves portable source, explicit revision and current publication metadata" do
    for {suffix, expected} <- [{"", 3}, {"?revision=1", 1}] do
      response = request(@path <> "/example" <> suffix, "full-key")
      assert response.status == 200
      assert_received {:fetch_revision, @tenant, "example", ^expected}
      result = JSON.decode!(response.resp_body)["call_spec"]
      assert result["call_spec_id"] == "example"
      assert result["source"] == %{"schema_version" => "20261004.01", "name" => "Portable"}
      assert result["revision"] == expected
      assert result["latest_revision"] == 3
      assert result["published_revision"] == 2
      assert result["published"] == false
      assert result["validation_errors"] == []
      refute response.resp_body =~ "private-compiled-sentinel"
      refute response.resp_body =~ "tenant_id"
    end
  end

  test "auth precedence and scope reject unauthorized reads before repository access" do
    for secret <- [nil, "invalid", "revoked", "vxop_legacy"] do
      assert request(@path, secret).status == 401
    end

    assert request(@path, "calls-key").status == 403
    assert request(String.replace(@path, @tenant, @other), "full-key").status == 403
    assert request(@path <> "/example", "calls-key").status == 403
    refute_received {:list_call_specs, _, _, _}
    refute_received {:fetch_revision, _, _, _}

    browser = {__MODULE__, self()}
    assert request(@path, nil, browser_auth: browser).status == 200
    assert_received :browser_authenticated

    denied =
      request(@path, nil, browser_auth: browser, headers: [{"authorization", "Basic invalid"}])

    assert denied.status == 401
    refute_received :browser_authenticated
  end

  test "new page bounds, missing records and failures use safe errors and keep browser hooks" do
    for query <- ["page=0", "page=2147483648", "page_size=51", "page_size[]=1", "q=x"] do
      response = request(@path <> "?" <> query, nil, browser_auth: {__MODULE__, self()})
      assert response.status == 422
      assert JSON.decode!(response.resp_body)["error"]["code"] == "invalid_page"
      assert get_resp_header(response, "x-browser-response") == ["preserved"]
    end

    refute_received {:list_call_specs, _, _, _}

    assert request(@path <> "?page=2", "full-key", empty: true).status == 422
    empty = request(@path, "full-key", empty: true)
    assert JSON.decode!(empty.resp_body)["pagination"]["total_pages"] == 0

    for query <- ["revision=0", "revision=2147483648", "revision[]=1", "api_key=x"] do
      assert request(@path <> "/example?" <> query, "full-key").status == 400
    end

    assert request(@path <> "/missing", "full-key").status == 404

    for failure <- [:raised, :returned] do
      response = request(@path, "full-key", failure: failure)
      assert response.status == 503
      refute response.resp_body =~ "private"
    end

    assert request(@path, "full-key", enabled: false).status == 404
  end

  test "mount forwards the read configuration" do
    options =
      Vxpipe.Gateway.HTTP.Mount.init(path_prefix: "/voice", call_spec_reads: [enabled: true])

    response = conn(:get, "/voice" <> @path) |> Vxpipe.Gateway.HTTP.Mount.call(options)
    assert response.status == 401
    assert response.halted
  end

  def authenticate(conn, observer) do
    send(observer, :browser_authenticated)
    conn = register_before_send(conn, &put_resp_header(&1, "x-browser-response", "preserved"))

    {:ok, conn,
     %Vxpipe.Identity.Principal{
       user_public_id: "user",
       session_public_id: "session",
       account_kind: :member,
       grants: MapSet.new(["call_specs.read"]),
       assigned_tenants: %{@tenant => :read},
       all_tenant_actions: MapSet.new()
     }}
  end

  def fetch_api_key_by_digest(_context, digest) do
    case Enum.find(["full-key", "calls-key", "revoked"], &(:crypto.hash(:sha256, &1) == digest)) do
      nil ->
        {:error, :not_found}

      secret ->
        {:ok,
         %{
           id: "key",
           tenant_key: @tenant,
           scopes: MapSet.new(if(secret == "calls-key", do: [:calls], else: [:admin])),
           revoked_at: if(secret == "revoked", do: ~U[2026-10-15 00:00:00Z])
         }}
    end
  end

  def authenticate_platform(_context, digest) do
    if digest == :crypto.hash(:sha256, @platform),
      do: {:ok, "platform"},
      else: {:error, :invalid_api_key}
  end

  def list_call_specs(context, tenant, limit, offset) do
    send(context.observer, {:list_call_specs, tenant, limit, offset})

    case context.failure do
      :raised ->
        raise "private storage failure"

      :returned ->
        {:error, {:private, "database"}}

      nil ->
        summaries =
          if context.empty,
            do: [],
            else: [
              %CallSpecSummary{
                id: "example",
                name: "Example spec",
                latest_revision: 3,
                published_revision: 2,
                call_count: 4,
                updated_at: ~U[2026-10-15 00:00:00Z]
              }
            ]

        {:ok,
         {%Tenant{key: tenant, name: "Example", inserted_at: ~U[2026-10-15 00:00:00Z]}, summaries,
          if(context.empty, do: 0, else: 3)}}
    end
  end

  def next_revision(_context, _tenant, "missing"), do: {:ok, 1}
  def next_revision(_context, _tenant, _id), do: {:ok, 4}

  def fetch_revision(context, tenant, id, version) do
    send(context.observer, {:fetch_revision, tenant, id, version})

    {:ok,
     %CallSpecRevision{
       tenant_key: tenant,
       call_spec_id: id,
       revision: version,
       schema_version: "20261004.01",
       source: %{"schema_version" => "20261004.01", "name" => "Portable"},
       source_digest: "digest",
       compiled_metadata: %{private: "private-compiled-sentinel"},
       validation_errors: [],
       routes: [],
       telephony_routes: [],
       published_at: nil,
       inserted_at: ~U[2026-10-15 00:00:00Z]
     }}
  end

  def fetch_published_revision(_context, _tenant, _id), do: {:ok, %{revision: 2}}

  defp request(path, secret, options \\ []) do
    context = %{
      observer: self(),
      empty: Keyword.get(options, :empty, false),
      failure: Keyword.get(options, :failure)
    }

    endpoint =
      Endpoint.init(
        call_spec_reads: [
          enabled: Keyword.get(options, :enabled, true),
          browser_auth: Keyword.get(options, :browser_auth),
          calls_options:
            Enum.map(
              [
                :credential_repository,
                :access_key_repository,
                :admin_repository,
                :call_spec_repository
              ],
              &{&1, {__MODULE__, context}}
            )
        ]
      )

    headers =
      Keyword.get(
        options,
        :headers,
        if(secret, do: [{"authorization", "Bearer " <> secret}], else: [])
      )

    Endpoint.call(%{conn(:get, path) | req_headers: headers}, endpoint)
  end
end
