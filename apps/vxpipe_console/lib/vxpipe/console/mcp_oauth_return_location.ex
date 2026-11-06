defmodule Vxpipe.Console.MCPOAuthReturnLocation do
  @moduledoc "Bounded same-tenant Integrations navigation for an OAuth attempt."

  def validate(tenant, path) when is_binary(tenant) do
    if Regex.match?(~r/\A[A-Za-z0-9_-]{1,128}\z/, tenant),
      do: location("/t/#{tenant}/services", path),
      else: {:error, :invalid_oauth_return_location}
  end

  def validate(_, _), do: {:error, :invalid_oauth_return_location}

  def connected(tenant, path, attempt_id \\ nil),
    do: destination(tenant, path, "connected", attempt_id)

  def failed(tenant, path, reason, attempt_id \\ nil) do
    status = if reason == :oauth_consent_denied, do: "denied", else: "failed"
    destination(tenant, path, status, attempt_id)
  end

  defp destination(tenant, path, status, attempt_id) do
    destination =
      case validate(tenant, path) do
        {:ok, accepted} ->
          accepted

        _ ->
          case validate(tenant, nil) do
            {:ok, root} -> root
            _ -> "/"
          end
      end

    uri = URI.parse(destination)
    result = [{"mcp", status}] ++ attempt_parameter(attempt_id)
    query = URI.encode_query(result)
    query = if uri.query, do: uri.query <> "&" <> query, else: query
    URI.to_string(%{uri | query: query})
  end

  defp attempt_parameter(id) when is_binary(id) and byte_size(id) in 1..128 do
    if Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, id), do: [{"mcp_attempt", id}], else: []
  end

  defp attempt_parameter(_), do: []

  defp location(base, nil), do: {:ok, base}

  defp location(base, path) when is_binary(path) and byte_size(path) in 1..16_384 do
    with {:ok,
          %URI{scheme: nil, authority: nil, host: nil, userinfo: nil, port: nil, fragment: nil} =
            uri} <- URI.new(path),
         true <- valid_path?(base, uri.path),
         {:ok, query} <- query(uri.query) do
      {:ok, URI.to_string(%{uri | query: query})}
    else
      _ -> {:error, :invalid_oauth_return_location}
    end
  rescue
    _ -> {:error, :invalid_oauth_return_location}
  end

  defp location(_, _), do: {:error, :invalid_oauth_return_location}

  defp valid_path?(base, base), do: true

  defp valid_path?(base, path) when is_binary(path) do
    prefix = base <> "/"

    String.starts_with?(path, prefix) and
      Regex.match?(~r/\A[a-z][a-z0-9-]{0,63}\z/, String.replace_prefix(path, prefix, ""))
  end

  defp valid_path?(_, _), do: false

  defp query(nil), do: {:ok, nil}
  defp query(""), do: {:ok, nil}

  defp query(encoded) do
    pairs = Enum.to_list(URI.query_decoder(encoded))
    keys = Enum.map(pairs, &elem(&1, 0))

    if length(keys) == length(Enum.uniq(keys)) and Enum.all?(pairs, &valid_parameter?/1),
      do: {:ok, URI.encode_query(pairs)},
      else: {:error, :invalid_oauth_return_location}
  end

  defp valid_parameter?({"q", value}), do: safe_text?(value) and String.length(value) <= 200
  defp valid_parameter?({"cursor", value}), do: safe_text?(value) and byte_size(value) in 1..2048
  defp valid_parameter?(_), do: false

  defp safe_text?(value),
    do: String.valid?(value) and not Regex.match?(~r/[\x00-\x1F\x7F]/u, value)
end
