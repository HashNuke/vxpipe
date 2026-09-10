defmodule Vxpipe.MCP.Authentication do
  @moduledoc false

  @maximum_headers 32
  @maximum_name_bytes 128
  @maximum_value_bytes 8_192

  @transport_headers MapSet.new([
                       "accept",
                       "accept-encoding",
                       "connection",
                       "content-length",
                       "content-type",
                       "host",
                       "last-event-id",
                       "mcp-protocol-version",
                       "mcp-session-id",
                       "transfer-encoding",
                       "user-agent"
                     ])

  @type error :: :invalid_authentication

  @spec headers(nil | :none | keyword()) :: {:ok, [{String.t(), String.t()}]} | {:error, error()}
  def headers(authentication)

  def headers(nil), do: {:ok, []}
  def headers(:none), do: {:ok, []}

  def headers(authentication) when is_list(authentication) do
    case Keyword.get(authentication, :type) do
      :bearer -> bearer_headers(authentication)
      :custom_headers -> custom_headers(authentication)
      _unsupported -> {:error, :invalid_authentication}
    end
  end

  def headers(_authentication), do: {:error, :invalid_authentication}

  defp bearer_headers(authentication) do
    with {:ok, options} <- Keyword.validate(authentication, [:type, :token]),
         token when is_binary(token) <- Keyword.get(options, :token),
         true <- valid_bearer_token?(token) do
      {:ok, [{"authorization", "Bearer " <> token}]}
    else
      _invalid -> {:error, :invalid_authentication}
    end
  end

  defp custom_headers(authentication) do
    with {:ok, options} <- Keyword.validate(authentication, [:type, :headers]),
         headers when is_list(headers) <- Keyword.get(options, :headers),
         true <- length(headers) in 1..@maximum_headers,
         {:ok, normalized} <- normalize_headers(headers),
         true <- unique_names?(normalized) do
      {:ok, normalized}
    else
      _invalid -> {:error, :invalid_authentication}
    end
  end

  defp normalize_headers(headers) do
    Enum.reduce_while(headers, {:ok, []}, fn
      {name, value}, {:ok, normalized} ->
        name = if is_binary(name), do: String.downcase(name), else: name

        if valid_header_name?(name) and valid_header_value?(value) and
             not MapSet.member?(@transport_headers, name) do
          {:cont, {:ok, [{name, value} | normalized]}}
        else
          {:halt, {:error, :invalid_authentication}}
        end

      _invalid, _accumulator ->
        {:halt, {:error, :invalid_authentication}}
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, _reason} = error -> error
    end
  end

  defp valid_bearer_token?(token) do
    byte_size(token) in 1..@maximum_value_bytes and
      Regex.match?(~r/\A[A-Za-z0-9\-._~+\/]+=*\z/, token)
  end

  defp valid_header_name?(name) when is_binary(name) do
    byte_size(name) in 1..@maximum_name_bytes and
      Regex.match?(~r/\A[!#$%&'*+\-.^_`|~0-9a-z]+\z/, name)
  end

  defp valid_header_name?(_name), do: false

  defp valid_header_value?(value) when is_binary(value) do
    byte_size(value) in 1..@maximum_value_bytes and
      value
      |> :binary.bin_to_list()
      |> Enum.all?(&(&1 == 9 or &1 in 32..126))
  end

  defp valid_header_value?(_value), do: false

  defp unique_names?(headers) do
    names = Enum.map(headers, &elem(&1, 0))
    length(names) == length(Enum.uniq(names))
  end
end
