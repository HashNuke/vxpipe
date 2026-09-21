defmodule Vxpipe.CallEngine.TestSpeechCredentialSource do
  @moduledoc "Synthetic authentication for speech lifecycle tests using local transport doubles."
  @behaviour Vxpipe.CallEngine.CredentialSource

  @impl true
  def resolve(:synthetic, tenant_id, provider, name) when provider in ["deepgram", "google"] do
    {:ok,
     %Vxpipe.CallEngine.ProviderCredential{
       id: "synthetic-speech-credential",
       tenant_id: tenant_id,
       provider: provider,
       name: name,
       version: 1,
       auth_kind: "api_key",
       payload: %{"api_key" => "runtime-test-secret"}
     }}
  end

  def resolve(_context, _tenant_id, _provider, _name), do: {:error, :unavailable}
end
