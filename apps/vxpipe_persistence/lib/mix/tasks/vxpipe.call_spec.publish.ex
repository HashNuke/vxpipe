defmodule Mix.Tasks.Vxpipe.CallSpec.Publish do
  use Mix.Task

  alias Vxpipe.Persistence.CLI

  @shortdoc "Publishes one validated call-spec revision"
  @requirements ["app.config"]

  @impl true
  def run(arguments) do
    options =
      CLI.options!(
        arguments,
        [tenant: :string, call_spec_id: :string, revision: :string],
        [:tenant, :call_spec_id, :revision]
      )

    CLI.ensure_ready!()
    revision_number = CLI.positive_integer!(Keyword.fetch!(options, :revision), "revision")

    revision =
      Vxpipe.Calls.publish_call_spec(
        Keyword.fetch!(options, :tenant),
        Keyword.fetch!(options, :call_spec_id),
        revision_number
      )
      |> CLI.unwrap!()

    CLI.output!(CLI.revision_summary(revision))
  end
end
