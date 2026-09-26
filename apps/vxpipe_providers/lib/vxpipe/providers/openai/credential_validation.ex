defmodule Vxpipe.Providers.OpenAI.CredentialValidation do
  @moduledoc false
  @behaviour Vxpipe.Providers.CredentialValidation

  @impl true
  def request("api_key", %{"api_key" => api_key} = payload) when map_size(payload) == 1 do
    {:ok,
     [
       url: "https://api.openai.com/v1/models",
       headers: [{"authorization", "Bearer " <> api_key}, {"accept", "application/json"}]
     ]}
  end

  def request(_auth_kind, _payload), do: {:error, :provider_validation_unsupported}
end
