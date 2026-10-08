defmodule Vxpipe.Providers.Zenmux do
  @moduledoc "Zenmux's declared Vxpipe capabilities."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "zenmux"

  @impl true
  def capabilities do
    %{
      llm: Vxpipe.AgentRuntime.Provider.ReqLLM,
      credential: Vxpipe.Providers.Zenmux.Credential,
      credential_validation: Vxpipe.Providers.Zenmux.CredentialValidation
    }
  end
end
