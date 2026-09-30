defmodule Vxpipe.Providers.DeepSeek do
  @moduledoc "DeepSeek's declared service capabilities. Model inference belongs to ReqLLM."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "deepseek"

  @impl true
  def capabilities do
    %{
      credential: Vxpipe.Providers.APIKeyCredential,
      credential_validation: Vxpipe.Providers.DeepSeek.CredentialValidation
    }
  end
end
