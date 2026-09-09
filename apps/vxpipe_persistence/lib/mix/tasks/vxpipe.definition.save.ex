defmodule Mix.Tasks.Vxpipe.Definition.Save do
  use Mix.Task

  alias Vxpipe.Persistence.CLI

  @shortdoc "Saves an immutable call-definition draft revision"
  @requirements ["app.config"]

  @impl true
  def run(arguments) do
    options =
      CLI.options!(
        arguments,
        [tenant: :string, file: :string, definition_id: :string],
        [:tenant, :file]
      )

    CLI.ensure_ready!()
    source = options |> Keyword.fetch!(:file) |> CLI.read_json_file!()

    workflow_options =
      case Keyword.get(options, :definition_id) do
        nil -> []
        definition_id -> [definition_id: definition_id]
      end

    revision =
      Vxpipe.Calls.save_definition(
        Keyword.fetch!(options, :tenant),
        source,
        workflow_options
      )
      |> CLI.unwrap!()

    CLI.output!(CLI.revision_summary(revision))
  end
end
