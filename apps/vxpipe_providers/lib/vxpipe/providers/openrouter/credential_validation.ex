defmodule Vxpipe.Providers.OpenRouter.CredentialValidation do
  @moduledoc false
  @behaviour Vxpipe.Providers.CredentialValidation

  @impl true
  def request("api_key", %{"api_key" => api_key} = payload) when map_size(payload) == 1 do
    case Vxpipe.Providers.APIKeyCredential.validate("api_key", payload) do
      :ok ->
        {:ok,
         [
           url: "https://openrouter.ai/api/v1/key",
           headers: [{"accept", "application/json"}, {"authorization", "Bearer " <> api_key}]
         ]}

      _invalid ->
        {:error, :provider_validation_unsupported}
    end
  end

  def request(_kind, _payload), do: {:error, :provider_validation_unsupported}
end
