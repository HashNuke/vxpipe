defmodule Mix.Tasks.Vxpipe.CallSpec.Save do
  use Mix.Task

  alias Vxpipe.Persistence.CLI

  @shortdoc "Saves an immutable call-spec draft revision"
  @requirements ["app.config"]

  @impl true
  def run(arguments) do
    options =
      CLI.options!(
        arguments,
        [tenant: :string, file: :string, call_spec_id: :string],
        [:tenant, :file]
      )

    CLI.ensure_ready!()
    source = options |> Keyword.fetch!(:file) |> CLI.read_json_file!()

    workflow_options =
      case Keyword.get(options, :call_spec_id) do
        nil -> []
        call_spec_id -> [call_spec_id: call_spec_id]
      end

    revision =
      Vxpipe.Calls.save_call_spec(
        Keyword.fetch!(options, :tenant),
        source,
        workflow_options
      )
      |> CLI.unwrap!()

    CLI.output!(CLI.revision_summary(revision))
  end
end
