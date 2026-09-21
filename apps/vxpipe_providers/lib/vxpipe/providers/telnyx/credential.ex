defmodule Vxpipe.Providers.Telnyx.Credential do
  @moduledoc false
  @behaviour Vxpipe.Providers.Credential

  @impl true
  def auth_kind, do: "api_key"

  @impl true
  def validate("api_key", %{"api_key" => key, "public_key" => public_key} = payload)
      when map_size(payload) == 2 do
    with :ok <- validate("api_key", %{"api_key" => key}),
         true <- public_key?(public_key) do
      :ok
    else
      _invalid -> {:error, :invalid_provider_auth}
    end
  end

  def validate("api_key", %{"api_key" => key} = payload)
      when map_size(payload) == 1 and is_binary(key) and byte_size(key) <= 4_096 do
    if Regex.match?(~r/\A[\x21-\x7E]+\z/, key),
      do: :ok,
      else: {:error, :invalid_provider_auth}
  end

  def validate(_kind, _payload), do: {:error, :invalid_provider_auth}

  @doc false
  def public_key?(value) when is_binary(value) and byte_size(value) == 44 do
    case Base.decode64(value) do
      {:ok, decoded} when byte_size(decoded) == 32 -> true
      _invalid -> false
    end
  end

  def public_key?(_value), do: false
end
