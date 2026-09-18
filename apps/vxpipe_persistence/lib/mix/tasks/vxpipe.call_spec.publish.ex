defmodule Mix.Tasks.Vxpipe.Definition.Publish do
  use Mix.Task

  alias Vxpipe.Persistence.CLI

  @shortdoc "Publishes one validated call-definition revision"
  @requirements ["app.config"]

  @impl true
  def run(arguments) do
    options =
      CLI.options!(
        arguments,
        [tenant: :string, definition_id: :string, revision: :string],
        [:tenant, :definition_id, :revision]
      )

    CLI.ensure_ready!()
    revision_number = CLI.positive_integer!(Keyword.fetch!(options, :revision), "revision")

    revision =
      Vxpipe.Calls.publish_definition(
        Keyword.fetch!(options, :tenant),
        Keyword.fetch!(options, :definition_id),
        revision_number
      )
      |> CLI.unwrap!()

    CLI.output!(CLI.revision_summary(revision))
  end
end
