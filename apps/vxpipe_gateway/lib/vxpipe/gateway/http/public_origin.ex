defmodule Vxpipe.Gateway.HTTP.PublicOrigin do
  @moduledoc "Resolves allowlisted runtime settings into a public URL or local preview."

  alias Vxpipe.Gateway.Telephony.ConfiguredService

  @spec resolve(keyword()) :: {:ok, String.t()} | {:error, :invalid_public_origin}
  def resolve(options) do
    case Keyword.get(options, :override) do
      nil -> from_listener(options)
      override -> from_override(override)
    end
  end

  defp from_override(value) do
    with {:ok, _uri} <- URI.new(value),
         {:ok, url} <- ConfiguredService.normalize_public_base_url(value),
         uri = URI.parse(url),
         true <- valid_host?(uri.host) and valid_port?(uri.port) do
      {:ok, url}
    else
      _invalid -> {:error, :invalid_public_origin}
    end
  end

  defp from_listener(options) do
    host = options |> Keyword.get(:host) |> normalize_host()
    tls = Keyword.get(options, :tls)

    with true <- valid_host?(host),
         {port, ""} <- Integer.parse(to_string(Keyword.get(options, :port) || "4000")),
         true <- valid_port?(port) and tls in [nil, "http", "phoenix"] do
      local? = host in ["localhost", "127.0.0.1", "::1"]
      scheme = if tls == "phoenix" or (not local? and tls != "http"), do: "https", else: "http"
      public_port = if local? or not is_nil(tls), do: port, else: 443
      {:ok, URI.to_string(%URI{scheme: scheme, host: host, port: public_port})}
    else
      _invalid -> {:error, :invalid_public_origin}
    end
  end

  defp normalize_host(nil), do: "localhost"

  defp normalize_host(host) when is_binary(host) do
    host
    |> String.trim()
    |> String.downcase()
    |> String.trim_trailing(".")
    |> unbracket_ipv6()
  end

  defp normalize_host(_invalid), do: nil

  defp unbracket_ipv6(host) do
    case Regex.run(~r/\A\[([a-f0-9:.]+)\]\z/, host) do
      [_, address] ->
        if String.contains?(address, ":") and
             match?({:ok, _}, :inet.parse_address(String.to_charlist(address))),
           do: address,
           else: host

      _unbracketed ->
        host
    end
  end

  defp valid_host?(host) when is_binary(host) and byte_size(host) in 1..253 do
    match?({:ok, _}, :inet.parse_address(String.to_charlist(host))) or
      Enum.all?(
        String.split(host, "."),
        &Regex.match?(~r/\A[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\z/, &1)
      )
  end

  defp valid_host?(_invalid), do: false
  defp valid_port?(port), do: is_integer(port) and port in 1..65_535
end
