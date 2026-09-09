defmodule Mix.Tasks.Vxpipe.ApiKey.Issue do
  use Mix.Task

  alias Vxpipe.Persistence.CLI

  @shortdoc "Issues another independently revocable tenant API key"
  @requirements ["app.config"]

  @impl true
  def run(arguments) do
    options =
      CLI.options!(arguments, [tenant: :string, name: :string, scopes: :string], [
        :tenant,
        :name,
        :scopes
      ])

    CLI.ensure_ready!()

    issued =
      Vxpipe.Calls.issue_api_key(
        Keyword.fetch!(options, :tenant),
        Keyword.fetch!(options, :name),
        CLI.scopes!(Keyword.fetch!(options, :scopes))
      )
      |> CLI.unwrap!()

    CLI.output!(%{
      "tenant_key" => issued.tenant_key,
      "api_key_id" => issued.id,
      "api_key" => issued.secret,
      "scopes" => issued.scopes |> Enum.map(&Atom.to_string/1) |> Enum.sort(),
      "notice" => "Store api_key now; Vxpipe cannot recover it."
    })
  end
end
