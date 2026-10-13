defmodule Vxpipe.Identity.Tokens do
  @moduledoc "Opaque random session tokens. Only digests are stored."

  @token_bytes 32
  @session_ttl_seconds 12 * 3600

  @spec session_ttl_seconds() :: pos_integer()
  def session_ttl_seconds, do: @session_ttl_seconds

  @spec generate() :: {:ok, %{token: String.t(), digest: String.t()}}
  def generate do
    token = @token_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {:ok, %{token: token, digest: digest(token)}}
  end

  @spec digest(String.t()) :: String.t()
  def digest(token) when is_binary(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  @spec expiry(DateTime.t()) :: DateTime.t()
  def expiry(now), do: DateTime.add(now, @session_ttl_seconds, :second)
end
