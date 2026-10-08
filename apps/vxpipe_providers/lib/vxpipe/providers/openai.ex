defmodule Vxpipe.Providers.OpenAI do
  @moduledoc "OpenAI's declared Vxpipe capabilities."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "openai"

  @impl true
  def capabilities do
    %{
      llm: Vxpipe.AgentRuntime.Provider.ReqLLM,
      credential: Vxpipe.Providers.OpenAI.Credential,
      credential_validation: Vxpipe.Providers.OpenAI.CredentialValidation,
      sts: Vxpipe.Providers.OpenAI.GPTLiveSession
    }
  end
end
