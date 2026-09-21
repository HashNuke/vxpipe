defmodule Vxpipe.Providers.Rime.CredentialValidation do
  @moduledoc false

  @behaviour Vxpipe.Providers.CredentialValidation

  @impl true
  def request("api_key", %{"api_key" => api_key} = payload) when map_size(payload) == 1 do
    {:ok,
     [
       method: :post,
       url: "https://users.rime.ai/oov",
       json: %{text: "hello"},
       headers: [{"accept", "application/json"}, {"authorization", "Bearer " <> api_key}]
     ]}
  end

  def request(_auth_kind, _payload), do: {:error, :provider_validation_unsupported}
end
