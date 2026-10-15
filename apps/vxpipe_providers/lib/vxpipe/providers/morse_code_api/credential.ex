defmodule Vxpipe.Providers.MorseCodeApi.Credential do
  @moduledoc "Caller-chosen Morse compatibility keys, constrained only for safe HTTP transport."
  @behaviour Vxpipe.Providers.Credential

  @impl true
  defdelegate auth_kind(), to: Vxpipe.Providers.APIKeyCredential
  @impl true
  defdelegate preview_fields(), to: Vxpipe.Providers.APIKeyCredential

  @impl true
  def validate("api_key", %{"api_key" => key} = payload)
      when map_size(payload) == 1 and is_binary(key) and byte_size(key) <= 8_192 do
    if String.valid?(key) and String.trim(key) != "" and Regex.match?(~r/\A[\x20-\x7E]+\z/, key),
       do: :ok,
       else: {:error, :invalid_provider_auth}
  end

  def validate(_kind, _payload), do: {:error, :invalid_provider_auth}
end
