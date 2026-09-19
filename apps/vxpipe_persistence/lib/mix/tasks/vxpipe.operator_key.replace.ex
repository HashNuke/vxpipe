defmodule Mix.Tasks.Vxpipe.OperatorKey.Replace do
  use Mix.Task
  @shortdoc "Replaces the installation API key and revokes the previous key"
  @moduledoc "Run `mix vxpipe.operator_key.replace --output PATH`. Writes once to a new owner-only file."
  @requirements ["app.config"]
  @impl true
  def run(arguments), do: Vxpipe.Persistence.OperatorKeyCLI.issue(:replace, arguments)
end
