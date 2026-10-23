defmodule Vxpipe.Providers.MorseCodeApi.CredentialValidation do
  @moduledoc "Describes reachability of the configured Morse API, not API-key ownership."
  @behaviour Vxpipe.Providers.CredentialValidation
  alias Vxpipe.Providers.MorseCodeApi.{Credential, Endpoint}

  @impl true
  def request(kind, payload) do
    with :ok <- Credential.validate(kind, payload),
         {:ok, endpoint} <- Endpoint.configured() do
      {:ok,
       [
         url: endpoint.http <> "/v1/models",
         headers: [{"accept", "application/json"}, {"xi-api-key", Map.fetch!(payload, "api_key")}]
       ]}
    else
      {:error, :invalid_provider_auth} = error -> error
      _unavailable -> {:error, :provider_validation_unavailable}
    end
  end
end
