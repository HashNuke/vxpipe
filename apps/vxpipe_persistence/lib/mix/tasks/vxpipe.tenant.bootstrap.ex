defmodule Mix.Tasks.Vxpipe.Tenant.Bootstrap do
  use Mix.Task

  alias Vxpipe.Persistence.CLI

  @shortdoc "Creates a tenant and its first API key"
  @requirements ["app.config"]

  @impl true
  def run(arguments) do
    options = CLI.options!(arguments, [name: :string, scopes: :string], [:name, :scopes])
    CLI.ensure_ready!()

    {tenant, issued} =
      Vxpipe.Calls.bootstrap_tenant(
        Keyword.fetch!(options, :name),
        CLI.scopes!(Keyword.fetch!(options, :scopes))
      )
      |> CLI.unwrap_bootstrap!()

    CLI.output!(%{
      "tenant_key" => tenant.key,
      "api_key_id" => issued.id,
      "api_key" => issued.secret,
      "scopes" => issued.scopes |> Enum.map(&Atom.to_string/1) |> Enum.sort(),
      "notice" => "Store api_key now; Vxpipe cannot recover it."
    })
  end
end
