defmodule Vxpipe.Identity.InstallationURL do
  @moduledoc "Canonical public installation origin, independent of listener configuration."

  def normalize(value) when is_binary(value) and byte_size(value) <= 2_048 do
    value = String.trim(value)

    with true <- Regex.match?(~r/\Ahttps?:\/\/[^\/?#@]+(?:[\/?#].*)?\z/i, value),
         false <- Regex.match?(~r/[\s\\]/, value),
         {:ok, uri} <- URI.new(value),
         true <- is_binary(uri.host) and is_nil(uri.userinfo),
         scheme = String.downcase(uri.scheme),
         host = String.downcase(uri.host),
         true <- valid_host?(host) and uri.port in 1..65_535,
         true <-
           scheme == "https" or (scheme == "http" and host in ["localhost", "127.0.0.1", "::1"]) do
      {:ok, URI.to_string(%URI{scheme: scheme, host: host, port: uri.port})}
    else
      _ -> {:error, :invalid_public_url}
    end
  end

  def normalize(_), do: {:error, :invalid_public_url}

  defp valid_host?(host) when byte_size(host) in 1..253 do
    match?({:ok, _}, :inet.parse_address(String.to_charlist(host))) or
      Enum.all?(
        String.split(host, "."),
        &Regex.match?(~r/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i, &1)
      )
  end

  defp valid_host?(_), do: false
end
