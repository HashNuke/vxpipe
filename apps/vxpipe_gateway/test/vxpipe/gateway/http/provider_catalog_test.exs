defmodule Vxpipe.Gateway.HTTP.ProviderCatalogTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test
  alias Vxpipe.Calls.Principal
  alias Vxpipe.Gateway.HTTP.Endpoint

  @tenant "AAAAAAAAAAAAAAAA"
  @path "/api/tenants/#{@tenant}/providers"

  test "routes authenticated provider and model queries and disables caching" do
    response =
      request(@path <> "?capability=text_to_speech", "tenant-key", {:ok, %{providers: []}})

    assert response.status == 200
    assert JSON.decode!(response.resp_body) == %{"providers" => []}
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert_received {:providers, %Principal{tenant_key: @tenant}, @tenant, "text_to_speech"}

    response =
      request(
        @path <> "/deepgram/models?capability=text_to_speech",
        "tenant-key",
        {:ok, %{models: [%{id: "flux"}]}}
      )

    assert response.status == 200
    assert JSON.decode!(response.resp_body) == %{"models" => [%{"id" => "flux"}]}

    assert_received {:models, %Principal{tenant_key: @tenant}, @tenant, "deepgram",
                     "text_to_speech"}
  end

  test "rejects anonymous, invalid, insufficient and other-tenant credentials before listing" do
    for {path, key, status} <- [
          {@path, nil, 401},
          {@path, "wrong-key", 401},
          {@path, "calls-only", 403},
          {String.replace(@path, @tenant, "BBBBBBBBBBBBBBBB"), "tenant-key", 401}
        ] do
      assert request(path <> "?capability=text_to_speech", key, nil).status == status
    end

    refute_received {:providers, _, _, _}
    refute_received {:models, _, _, _, _}
  end

  test "projects catalog failures without leaking backend details" do
    for {reason, status, code} <- [
          {:invalid_capability, 422, "invalid_capability"},
          {:unsupported_provider, 404, "provider_not_found"},
          {:unsupported_provider_capability, 404, "provider_not_found"},
          {:tenant_not_found, 404, "tenant_not_found"},
          {{:database_error, "private-sentinel"}, 503, "provider_catalog_unavailable"}
        ] do
      response =
        request(@path <> "/unknown/models?capability=unknown", "tenant-key", {:error, reason})

      assert response.status == status
      assert JSON.decode!(response.resp_body) == %{"error" => %{"code" => code}}
    end

    assert request(@path, "tenant-key", :crash).status == 503
  end

  test "catalog follows the authoring feature gate" do
    assert conn(:get, @path) |> Endpoint.call(Endpoint.init([])) |> Map.fetch!(:status) == 404
  end

  test "browser catalog requests retain response hooks and explicit credentials never fall back" do
    browser_auth = {__MODULE__, self()}

    response =
      request(@path <> "?capability=text_to_speech", nil, {:ok, %{providers: []}}, browser_auth)

    assert response.status == 200
    assert_received :browser_authenticated
    assert get_resp_header(response, "x-browser-response") == ["preserved"]

    forbidden = request(@path, nil, {:error, :forbidden}, browser_auth)
    assert forbidden.status == 403
    assert JSON.decode!(forbidden.resp_body)["error"]["code"] == "authoring_forbidden"
    assert_received :browser_authenticated
    assert get_resp_header(forbidden, "x-browser-response") == ["preserved"]

    assert request(@path, "wrong-key", nil, browser_auth).status == 401
    refute_received :browser_authenticated
  end

  test "explicit pagination returns bounded items while unpaged catalogs preserve their envelope" do
    items = [%{id: "one"}, %{id: "two", voices: %{default: "voice"}}, %{id: "three"}]

    for {path, key} <- [{@path, :providers}, {@path <> "/morse/models", :models}] do
      response =
        request(
          path <> "?capability=text_to_speech&page=2&page_size=1",
          "tenant-key",
          {:ok, %{key => items}}
        )

      assert response.status == 200

      assert JSON.decode!(response.resp_body) == %{
               "items" => [%{"id" => "two", "voices" => %{"default" => "voice"}}],
               "pagination" => %{"page" => 2, "page_size" => 1, "total" => 3, "total_pages" => 3}
             }
    end

    empty = request(@path <> "?page=1", "tenant-key", {:ok, %{providers: []}})
    assert JSON.decode!(empty.resp_body)["pagination"]["total_pages"] == 0
    assert request(@path <> "?page=2", "tenant-key", {:ok, %{providers: []}}).status == 422
  end

  test "invalid catalog pagination is rejected before listing" do
    for query <- ["page=0", "page=2147483648", "page_size=51", "page[]=1", "page_size=x"] do
      response = request(@path <> "?" <> query, "tenant-key", {:ok, %{providers: []}})
      assert response.status == 422
      assert JSON.decode!(response.resp_body)["error"]["code"] == "invalid_page"
    end

    refute_received {:providers, _, _, _}
  end

  def authenticate(conn, observer) do
    send(observer, :browser_authenticated)
    conn = register_before_send(conn, &put_resp_header(&1, "x-browser-response", "preserved"))

    {:ok, conn,
     %Principal{tenant_key: @tenant, api_key_id: "browser-fixture", scopes: MapSet.new([:admin])}}
  end

  defp request(path, key, result, browser_auth \\ nil) do
    options =
      Endpoint.init(
        call_spec_authoring: [
          enabled: true,
          browser_auth: browser_auth,
          backend: {Vxpipe.Gateway.TestCallSpecAuthoringBackend, {self(), result}}
        ]
      )

    conn = conn(:get, path)
    conn = if key, do: put_req_header(conn, "authorization", "Bearer " <> key), else: conn
    Endpoint.call(conn, options)
  end
end
