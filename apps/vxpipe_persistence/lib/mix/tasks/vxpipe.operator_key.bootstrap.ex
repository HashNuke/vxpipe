defmodule Mix.Tasks.Vxpipe.OperatorKey.Bootstrap do
  use Mix.Task
  @shortdoc "Bootstraps an installation API key into a new protected output file"
  @moduledoc "Run `mix vxpipe.operator_key.bootstrap --output PATH`. Existing installations require explicit replacement."
  @requirements ["app.config"]
  @impl true
  def run(arguments), do: Vxpipe.Persistence.OperatorKeyCLI.issue(:bootstrap, arguments)
end
