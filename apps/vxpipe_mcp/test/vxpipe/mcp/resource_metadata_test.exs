defmodule Vxpipe.MCP.ResourceMetadataTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.ResourceMetadata
  @endpoint "https://mcp.example.test/public/mcp"

  test "challenge URL takes precedence and preserves scope and issuer choices" do
    owner = self()

    options =
      options(fn uri, _, _ ->
        send(owner, {:url, URI.to_string(uri)})

        case uri.path do
          "/public/mcp" ->
            response(401, "", [
              {"www-authenticate",
               ~s(Basic realm="a,b", Bearer resource_metadata="https://mcp.example.test/metadata", scope="tools:read")}
            ])

          "/metadata" ->
            response(200, metadata())
        end
      end)

    assert {:ok, result} = ResourceMetadata.discover(@endpoint, options)

    assert result["authorization_servers"] == [
             "https://auth.example.test/a",
             "https://auth.example.test/b"
           ]

    assert result["challenge_scope"] == "tools:read"
    assert_receive {:url, @endpoint}
    assert_receive {:url, "https://mcp.example.test/metadata"}
    refute_received {:url, _}
  end

  test "missing challenge tries path then root and missing metadata never means anonymous" do
    owner = self()

    options =
      options(fn uri, _, _ ->
        send(owner, {:path, uri.path})
        response(404, "")
      end)

    assert {:error, :resource_metadata_missing} = ResourceMetadata.discover(@endpoint, options)
    assert_receive {:path, "/public/mcp"}
    assert_receive {:path, "/.well-known/oauth-protected-resource/public/mcp"}
    assert_receive {:path, "/.well-known/oauth-protected-resource"}
  end

  test "substituted resource and ambiguous challenge fail closed" do
    options =
      options(fn uri, _, _ ->
        if uri.path == "/public/mcp",
          do: response(401, ""),
          else: response(200, Map.put(metadata(), "resource", "https://other.test/mcp"))
      end)

    assert {:error, :invalid_resource_metadata} = ResourceMetadata.discover(@endpoint, options)

    options =
      options(fn _, _, _ ->
        response(401, "", [
          {"www-authenticate",
           ~s(Bearer resource_metadata="https://mcp.example.test/a", resource_metadata="https://mcp.example.test/b")}
        ])
      end)

    assert {:error, :invalid_resource_challenge} = ResourceMetadata.discover(@endpoint, options)
  end

  test "a bare Bearer challenge permits well-known discovery while duplicate challenges remain ambiguous" do
    owner = self()

    for challenge <- [
          "Bearer",
          "bEaReR",
          " , Bearer , ",
          "Basic realm=\"a,b\", Bearer",
          "Bearer, Basic realm=\"other\""
        ] do
      opts =
        options(fn uri, _, _ ->
          send(owner, {:path, uri.path})

          if uri.path == "/public/mcp",
            do: response(401, "", [{"www-authenticate", challenge}]),
            else: response(200, metadata())
        end)

      assert {:ok, _} = ResourceMetadata.discover(@endpoint, opts)
      assert_receive {:path, "/public/mcp"}
      assert_receive {:path, "/.well-known/oauth-protected-resource/public/mcp"}
      refute_received {:path, _}
    end

    for challenge <- [
          "Bearer, bearer",
          "Bearer, Bearer scope=\"read\"",
          "Bearer, scope=read",
          " , "
        ] do
      opts = options(fn _, _, _ -> response(401, "", [{"www-authenticate", challenge}]) end)
      assert {:error, :invalid_resource_challenge} = ResourceMetadata.discover(@endpoint, opts)
    end
  end

  test "challenge parameters accept permitted whitespace without weakening duplicate rejection" do
    owner = self()

    challenge =
      "Basic realm=\"a = b, c\", Bearer resource_metadata \t= \t\"https://mcp.example.test/metadata\", scope = \"tools:read tools:write\""

    opts =
      options(fn uri, _, _ ->
        send(owner, {:path, uri.path})

        if uri.path == "/public/mcp",
          do: response(401, "", [{"www-authenticate", challenge}]),
          else: response(200, metadata())
      end)

    assert {:ok, found} = ResourceMetadata.discover(@endpoint, opts)
    assert found["challenge_scope"] == "tools:read tools:write"
    assert_receive {:path, "/public/mcp"}
    assert_receive {:path, "/metadata"}
    refute_received {:path, _}

    duplicate = challenge <> ", SCOPE = \"other\""
    opts = options(fn _, _, _ -> response(401, "", [{"www-authenticate", duplicate}]) end)
    assert {:error, :invalid_resource_challenge} = ResourceMetadata.discover(@endpoint, opts)
  end

  test "challenge scope rejects invalid text and non-token characters" do
    for scope <- [
          <<255>>,
          "",
          "read  write",
          " read",
          "read ",
          "read\\\\write",
          String.duplicate("x", 257)
        ] do
      opts =
        options(fn uri, _, _ ->
          if uri.path == "/public/mcp",
            do: response(401, "", [{"www-authenticate", "Bearer scope=\"" <> scope <> "\""}]),
            else: response(200, metadata())
        end)

      assert {:error, :invalid_resource_challenge} = ResourceMetadata.discover(@endpoint, opts)
    end
  end

  test "protected-resource advertised scopes use the same bounded scope-token contract" do
    for scopes <- [["two scopes"], ["bad\\scope"], ["bad\"scope"], ["non-ascii-í"]] do
      opts =
        options(fn uri, _, _ ->
          if uri.path == "/public/mcp",
            do: response(401, ""),
            else: response(200, Map.put(metadata(), "scopes_supported", scopes))
        end)

      assert {:error, :invalid_resource_metadata} = ResourceMetadata.discover(@endpoint, opts)
    end
  end

  defp options(client),
    do: [dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end, http_client: client]

  defp response(status, body, headers \\ []),
    do:
      {:ok,
       %{
         status: status,
         headers: headers,
         body: if(is_map(body), do: JSON.encode!(body), else: body)
       }}

  defp metadata,
    do: %{
      "resource" => @endpoint,
      "authorization_servers" => ["https://auth.example.test/a", "https://auth.example.test/b"],
      "scopes_supported" => ["tools:read"]
    }
end
