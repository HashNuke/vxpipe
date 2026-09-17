defmodule Vxpipe.Console.OperatorLoginConfiguration do
  @moduledoc "Validates the external origin and derives the operator-login verifier secret."

  alias Vxpipe.Console.Endpoint

  @derive {Inspect, only: [:origin]}
  @enforce_keys [:origin, :verifier_secret]
  defstruct @enforce_keys

  @minimum_secret_bytes 64
  @secret_label "vxpipe.operator-login.challenge-secret.v1"
  @loopback_hosts ["localhost", "127.0.0.1", "::1"]
  @url_options [:scheme, :host, :port, :path]

  @type t :: %__MODULE__{origin: String.t(), verifier_secret: binary()}

  @spec load() :: {:ok, t()} | {:error, atom()}
  def load do
    endpoint = Application.fetch_env!(:vxpipe_console, Endpoint)
    deployment_secret = Application.get_env(:vxpipe_console, :operator_login_secret)
    build(Keyword.get(endpoint, :url), deployment_secret)
  end

  @spec build(keyword() | term(), binary() | term()) :: {:ok, t()} | {:error, atom()}
  def build(url, deployment_secret) do
    with {:ok, origin} <- origin(url),
         :ok <- validate_secret(deployment_secret) do
      verifier_secret = :crypto.mac(:hmac, :sha256, deployment_secret, @secret_label)
      {:ok, %__MODULE__{origin: origin, verifier_secret: verifier_secret}}
    end
  end

  defp origin(url) when is_list(url) do
    if Keyword.keyword?(url) and valid_url_options?(url),
      do: build_origin(url),
      else: {:error, :invalid_operator_login_origin}
  end

  defp origin(_url), do: {:error, :invalid_operator_login_origin}

  defp build_origin(url) do
    scheme = Keyword.get(url, :scheme)
    host = normalize_host(Keyword.get(url, :host))
    port = Keyword.get(url, :port)
    path = Keyword.get(url, :path)

    with true <- scheme in ["http", "https"],
         true <- valid_host?(host),
         true <- valid_port?(port),
         true <- path in [nil, "", "/"],
         true <- secure_origin?(scheme, host) do
      uri = %URI{scheme: scheme, host: host, port: port}
      {:ok, URI.to_string(uri)}
    else
      _invalid -> {:error, :invalid_operator_login_origin}
    end
  end

  defp valid_url_options?(url) do
    keys = Keyword.keys(url)
    Enum.all?(keys, &(&1 in @url_options)) and length(keys) == length(Enum.uniq(keys))
  end

  defp normalize_host(host) when is_binary(host) do
    host
    |> String.downcase()
    |> String.trim_trailing(".")
  end

  defp normalize_host(_host), do: nil

  defp valid_host?(host) when is_binary(host) and host != "" and byte_size(host) <= 253 do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, _address} -> true
      {:error, _reason} -> valid_dns_host?(host)
    end
  end

  defp valid_host?(_host), do: false

  defp valid_dns_host?(host) do
    host
    |> String.split(".", trim: false)
    |> Enum.all?(&String.match?(&1, ~r/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/))
  end

  defp valid_port?(nil), do: true
  defp valid_port?(port), do: is_integer(port) and port in 1..65_535

  defp secure_origin?("https", _host), do: true
  defp secure_origin?("http", host), do: host in @loopback_hosts

  defp validate_secret(secret)
       when is_binary(secret) and byte_size(secret) >= @minimum_secret_bytes,
       do: :ok

  defp validate_secret(_secret), do: {:error, :invalid_operator_login_secret}
end
