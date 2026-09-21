defmodule Vxpipe.Console.Provider.Google.CredentialValidation do
  @moduledoc false

  @behaviour Vxpipe.Console.Provider.CredentialValidation

  @impl true
  def request("api_key", %{"api_key" => api_key} = payload) when map_size(payload) == 1 do
    {:ok,
     [
       url: "https://generativelanguage.googleapis.com/v1beta/models",
       params: [pageSize: 1],
       headers: [{"accept", "application/json"}, {"x-goog-api-key", api_key}]
     ]}
  end

  def request(_auth_kind, _payload), do: {:error, :provider_validation_unsupported}
end
