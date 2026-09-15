defmodule Mix.Tasks.Vxpipe.ProviderCredential.List do
  use Mix.Task

  alias Vxpipe.Calls.ProviderCredentials
  alias Vxpipe.Persistence.{CLI, ProviderCredentialCLI}

  @shortdoc "Lists tenant provider credential metadata without decrypting payloads"
  @requirements ["app.config"]

  @impl true
  def run(arguments) do
    options = ProviderCredentialCLI.options!(arguments, :list)
    CLI.ensure_ready!()

    ProviderCredentials.list(Keyword.fetch!(options, :tenant))
    |> CLI.unwrap!()
    |> Enum.map(&ProviderCredentialCLI.summary/1)
    |> CLI.output!()
  end
end
