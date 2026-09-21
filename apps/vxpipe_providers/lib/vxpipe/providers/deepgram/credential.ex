defmodule Vxpipe.Providers.Deepgram.Credential do
  @moduledoc false
  @behaviour Vxpipe.Providers.Credential

  @impl true
  def validate("api_key", %{"api_key" => key} = payload)
      when map_size(payload) == 1 and is_binary(key) and byte_size(key) <= 8_192 do
    if Regex.match?(~r/\A[\x21-\x7E]+\z/, key),
      do: :ok,
      else: {:error, :invalid_provider_auth}
  end

  def validate(_kind, _payload), do: {:error, :invalid_provider_auth}
end
