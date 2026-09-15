defmodule Mix.Tasks.Vxpipe.ProviderCredential.Provision do
  use Mix.Task

  alias Vxpipe.Calls.ProviderCredentials
  alias Vxpipe.Persistence.{CLI, ProviderCredentialCLI}

  @shortdoc "Provisions a tenant provider credential from protected JSON stdin"
  @requirements ["app.config"]

  @moduledoc """
  Provisions Google, Deepgram, Zenmux or Telnyx API keys, or existing Twilio Account SID/Auth
  Token auth using a JSON object on stdin. Twilio requires --auth-kind account_sid_auth_token.
  Requires --tenant and --provider; --name defaults to default and --auth-kind to api_key.
  Output contains metadata only. Run through a trusted operator session, using a secret manager
  pipe or a protected input descriptor. No command-line secret flags are accepted.
  """

  @impl true
  def run(arguments) do
    options = ProviderCredentialCLI.options!(arguments, :provision)
    payload = ProviderCredentialCLI.payload!()
    CLI.ensure_ready!()

    ProviderCredentials.provision(
      Keyword.fetch!(options, :tenant),
      Keyword.fetch!(options, :provider),
      Keyword.get(options, :name, "default"),
      Keyword.get(options, :auth_kind, "api_key"),
      payload
    )
    |> CLI.unwrap!()
    |> ProviderCredentialCLI.summary()
    |> CLI.output!()
  end
end
