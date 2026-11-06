defmodule Vxpipe.MCP.MachinePreflightTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.Preflight

  @endpoint "https://mcp.example.test/mcp"
  @issuer "https://auth.example.test"

  test "machine-only discovery suggests Own-client without authorizing or registering" do
    owner = self()

    for method <- ~w(client_secret_basic client_secret_post private_key_jwt) do
      metadata = %{
        "issuer" => @issuer,
        "token_endpoint" => @issuer <> "/token",
        "grant_types_supported" => ["client_credentials"],
        "token_endpoint_auth_methods_supported" => [method],
        "token_endpoint_auth_signing_alg_values_supported" => ["RS256"]
      }

      assert {:ok, result} = Preflight.discover("tenant", input(), options(metadata, owner))
      assert result.outcome == :oauth
      assert result.suggested_method == "own_client"
      assert result.supported_grants == ["client_credentials"]
      refute Map.has_key?(result.oauth, "authorization_endpoint")
      refute_received :anonymous
      refute_received :side_effect
    end
  end

  test "public-only or unsupported machine authentication remains unavailable" do
    for metadata <- [
          %{"token_endpoint_auth_methods_supported" => ["none"]},
          %{
            "token_endpoint_auth_methods_supported" => ["private_key_jwt"],
            "token_endpoint_auth_signing_alg_values_supported" => ["unsupported"]
          }
        ] do
      metadata =
        Map.merge(
          %{
            "issuer" => @issuer,
            "token_endpoint" => @issuer <> "/token",
            "grant_types_supported" => ["client_credentials"]
          },
          metadata
        )

      assert {:ok, result} = Preflight.discover("tenant", input(), options(metadata, self()))
      assert result.outcome == :unsupported_oauth
      assert result.suggested_method == nil
      refute_received :anonymous
      refute_received :side_effect
    end
  end

  defp input, do: %{"endpoint" => @endpoint, "revision" => "draft"}

  defp options(metadata, owner),
    do: [
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      http_client: fn uri, _, _ ->
        case {uri.host, uri.path} do
          {_, "/mcp"} ->
            response(401, %{})

          {"mcp.example.test", _} ->
            response(200, %{
              "resource" => @endpoint,
              "authorization_servers" => [@issuer]
            })

          _ ->
            response(200, metadata)
        end
      end,
      anonymous_check: fn _, _ ->
        send(owner, :anonymous)
        {:error, :failed}
      end,
      request_fun: fn _, _, _, _ ->
        send(owner, :side_effect)
        {:error, :unexpected}
      end
    ]

  defp response(status, body), do: {:ok, %{status: status, headers: [], body: JSON.encode!(body)}}
end
