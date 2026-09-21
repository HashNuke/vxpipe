defmodule Vxpipe.Console.Provider.Zenmux.CredentialValidation do
  @moduledoc false

  @behaviour Vxpipe.Console.Provider.CredentialValidation

  @impl true
  def request("api_key", %{"api_key" => api_key} = payload) when map_size(payload) == 1 do
    {:ok,
     [
       url: "https://zenmux.ai/api/v1/models",
       headers: [{"accept", "application/json"}, {"authorization", "Bearer " <> api_key}]
     ]}
  end

  def request(_auth_kind, _payload), do: {:error, :provider_validation_unsupported}
end
