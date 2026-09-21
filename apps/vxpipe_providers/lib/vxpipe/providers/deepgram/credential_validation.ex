defmodule Vxpipe.Providers.Deepgram.CredentialValidation do
  @moduledoc false
  @behaviour Vxpipe.Providers.CredentialValidation

  @impl true
  def request("api_key", %{"api_key" => api_key} = payload) when map_size(payload) == 1 do
    {:ok,
     [
       url: "https://api.deepgram.com/v1/projects",
       headers: [{"accept", "application/json"}, {"authorization", "Token " <> api_key}]
     ]}
  end

  def request(_kind, _payload), do: {:error, :provider_validation_unsupported}
end
