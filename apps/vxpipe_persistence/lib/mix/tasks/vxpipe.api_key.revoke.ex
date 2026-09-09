defmodule Mix.Tasks.Vxpipe.ApiKey.Revoke do
  use Mix.Task

  alias Vxpipe.Persistence.CLI

  @shortdoc "Revokes one tenant API key"
  @requirements ["app.config"]

  @impl true
  def run(arguments) do
    options =
      CLI.options!(arguments, [tenant: :string, key_id: :string], [:tenant, :key_id])

    CLI.ensure_ready!()

    revoked =
      Vxpipe.Calls.revoke_api_key(
        Keyword.fetch!(options, :tenant),
        Keyword.fetch!(options, :key_id)
      )
      |> CLI.unwrap!()

    CLI.output!(%{
      "tenant_key" => revoked.tenant_key,
      "api_key_id" => revoked.id,
      "revoked" => true,
      "revoked_at" => DateTime.to_iso8601(revoked.revoked_at)
    })
  end
end
