defmodule Vxpipe.Providers.OpenAI do
  @moduledoc "OpenAI's declared Vxpipe capabilities."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "openai"

  @impl true
  def capabilities do
    %{
      credential: Vxpipe.Providers.OpenAI.Credential,
      credential_validation: Vxpipe.Providers.OpenAI.CredentialValidation,
      sts: Vxpipe.Providers.OpenAI.GPTLiveSession
    }
  end
end
