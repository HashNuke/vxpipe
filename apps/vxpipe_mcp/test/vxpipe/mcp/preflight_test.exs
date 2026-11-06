defmodule Vxpipe.MCP.PreflightTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.Preflight
  @endpoint "https://mcp.example.test/mcp"
  @issuer "https://auth.example.test"

  test "URL/revision are echoed and multiple issuers require explicit choice" do
    options = options([@issuer, @issuer <> "/other"])
    assert {:ok, result} = Preflight.discover("tenant", input(), options)
    assert result.endpoint == @endpoint
    assert result.revision == "draft-2"
    assert result.outcome == :issuer_required
    assert result.issuers == [@issuer, @issuer <> "/other"]
    refute_received :oauth_fetch
  end

  test "selected issuer must be advertised; successful metadata suggests CIMD without registration" do
    options = options([@issuer, @issuer <> "/other"])

    assert {:error, :invalid_oauth_issuer} =
             Preflight.discover(
               "tenant",
               Map.put(input(), "issuer", "https://attacker.test"),
               options
             )

    refute_received :oauth_fetch

    assert {:ok, result} =
             Preflight.discover("tenant", Map.put(input(), "issuer", @issuer), options)

    assert result.outcome == :oauth
    assert result.suggested_method == "cimd"
    assert result.oauth["issuer"] == @issuer
    assert_receive :oauth_fetch
    refute_received :anonymous_check
  end

  test "missing metadata needs successful anonymous initialization before suggesting none" do
    owner = self()

    options = [
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      http_client: fn _, _, _ -> response(404, "") end,
      anonymous_check: fn tenant, config ->
        send(owner, {:checked, tenant, config.auth_method})
        {:ok, %{server_name: "Tools", catalog: []}}
      end
    ]

    assert {:ok, %{outcome: :anonymous, suggested_method: "none", server_name: "Tools"}} =
             Preflight.discover("tenant", input(), options)

    assert_receive {:checked, "tenant", "none"}

    options =
      Keyword.put(options, :anonymous_check, fn _, _ -> {:error, :mcp_connection_failed} end)

    assert {:ok, %{outcome: :unknown, suggested_method: nil}} =
             Preflight.discover("tenant", input(), options)
  end

  test "preflight rejects credential input and invalid revisions" do
    assert {:error, :invalid_mcp_preflight} =
             Preflight.discover("tenant", Map.put(input(), "credentials", %{}))

    assert {:error, :invalid_mcp_preflight} =
             Preflight.discover("tenant", Map.put(input(), "revision", ""))

    owner = self()

    assert {:error, :invalid_mcp_endpoint} =
             Preflight.discover(
               "tenant",
               Map.put(input(), "endpoint", @endpoint <> "?access_token=synthetic-private"),
               dns_resolver: fn _, _ ->
                 send(owner, :unexpected_dns)
                 {:error, :unexpected}
               end
             )

    refute_received :unexpected_dns
  end

  test "an explicit issuer supports manual discovery only when resource metadata is missing" do
    options = resource_response(404, "")

    assert {:ok, result} =
             Preflight.discover("tenant", Map.put(input(), "issuer", @issuer), options)

    assert result.outcome == :oauth
    assert result.oauth["issuer"] == @issuer
    assert result.suggested_method == "own_client"
    assert result.issuers == [@issuer]
    assert_receive :oauth_fetch
    refute_received :anonymous_check
  end

  test "manual issuer never bypasses malformed, conflicting or unavailable resource metadata" do
    for {status, body} <- [
          {200, %{"resource" => "https://different.test", "authorization_servers" => [@issuer]}},
          {200, %{"resource" => @endpoint, "authorization_servers" => ["http://insecure.test"]}},
          {503, ""}
        ] do
      assert {:ok, %{outcome: :unknown, suggested_method: nil}} =
               Preflight.discover(
                 "tenant",
                 Map.put(input(), "issuer", @issuer),
                 resource_response(status, body)
               )

      refute_received :oauth_fetch
      refute_received :anonymous_check
    end
  end

  test "invalid manual issuers fail before discovery and never appear in a partial result" do
    owner = self()

    for issuer <- [
          "https://auth.example.test/" <> String.duplicate("x", 2048),
          "https://auth.example.test/" <> <<255>>,
          "https://user:secret@auth.example.test",
          "https://auth.example.test?secret=hidden",
          "https://auth.example.test#fragment",
          "http://auth.example.test"
        ] do
      assert {:error, :invalid_mcp_preflight} =
               Preflight.discover(
                 "tenant",
                 Map.put(input(), "issuer", issuer),
                 dns_resolver: fn _, _ ->
                   send(owner, :unexpected_dns)
                   {:error, :unexpected}
                 end
               )

      refute_received :unexpected_dns
    end
  end

  defp resource_response(status, body) do
    options = options([@issuer])
    http = Keyword.fetch!(options, :http_client)

    Keyword.put(options, :http_client, fn uri, address, opts ->
      if uri.host == "mcp.example.test" and uri.path != "/mcp",
        do: response(status, body),
        else: http.(uri, address, opts)
    end)
  end

  defp input, do: %{"endpoint" => @endpoint, "revision" => "draft-2"}

  test "discovery does not suggest OAuth without issuer-response protection" do
    assert {:ok, result} = Preflight.discover("tenant", input(), options([@issuer], false))
    assert result.outcome == :unsupported_oauth
    assert result.suggested_method == nil
    assert result.reason == :unsupported_oauth_capabilities
    refute_received :anonymous_check
  end

  defp options(issuers, issuer_response \\ true) do
    owner = self()

    [
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      http_client: fn uri, _, _ ->
        cond do
          uri.path == "/mcp" ->
            response(401, "")

          uri.host == "mcp.example.test" ->
            response(200, %{"resource" => @endpoint, "authorization_servers" => issuers})

          true ->
            send(owner, :oauth_fetch)

            response(200, %{
              "issuer" => @issuer,
              "authorization_endpoint" => @issuer <> "/authorize",
              "token_endpoint" => @issuer <> "/token",
              "client_id_metadata_document_supported" => true,
              "code_challenge_methods_supported" => ["S256"],
              "response_types_supported" => ["code"],
              "authorization_response_iss_parameter_supported" => issuer_response
            })
        end
      end,
      anonymous_check: fn _, _ ->
        send(owner, :anonymous_check)
        {:error, :failed}
      end
    ]
  end

  defp response(status, body),
    do:
      {:ok,
       %{status: status, headers: [], body: if(is_map(body), do: JSON.encode!(body), else: body)}}
end
