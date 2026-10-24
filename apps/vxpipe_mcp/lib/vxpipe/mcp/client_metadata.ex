defmodule Vxpipe.MCP.ClientMetadata do
  @moduledoc "Public metadata for this installation as an outbound MCP OAuth client."

  @document_path "/oauth/client-metadata.json"
  @callback_path "/oauth/mcp/callback"

  def document(origin) do
    with :ok <- canonical_https_origin(origin) do
      {:ok, %{
        client_id: origin <> @document_path,
        client_name: "VxPipe",
        client_uri: origin,
        redirect_uris: [origin <> @callback_path],
        grant_types: ["authorization_code", "refresh_token"],
        response_types: ["code"],
        token_endpoint_auth_method: "none"
      }}
    end
  end

  @doc "Metadata payload for servers that require Dynamic Client Registration."
  def registration(origin) do
    with {:ok, metadata} <- document(origin), do: {:ok, Map.delete(metadata, :client_id)}
  end

  defp canonical_https_origin(origin) when is_binary(origin) do
    with {:ok, %URI{scheme: "https", host: host, port: port} = uri} <- URI.new(origin),
         true <- is_binary(host) and host != "" and port in 1..65_535,
         true <- is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment),
         true <- uri.path in [nil, ""],
         false <- String.contains?(origin, ["\\", " ", "\r", "\n", "\t"]),
         true <- URI.to_string(uri) == origin do
      :ok
    else
      _invalid -> {:error, :invalid_public_url}
    end
  end

  defp canonical_https_origin(_origin), do: {:error, :invalid_public_url}
end
