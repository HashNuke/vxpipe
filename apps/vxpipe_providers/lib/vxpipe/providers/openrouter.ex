defmodule Vxpipe.Providers.OpenRouter do
  @moduledoc "OpenRouter's declared service capabilities. Model inference belongs to ReqLLM."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "openrouter"

  @impl true
  def capabilities do
    %{
      credential: Vxpipe.Providers.APIKeyCredential,
      credential_validation: Vxpipe.Providers.OpenRouter.CredentialValidation
    }
  end
end
