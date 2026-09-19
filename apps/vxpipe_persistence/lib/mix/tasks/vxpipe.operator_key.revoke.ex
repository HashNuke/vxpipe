defmodule Mix.Tasks.Vxpipe.OperatorKey.Revoke do
  use Mix.Task
  alias Vxpipe.Persistence.{CLI, OperatorKeyCLI}
  @shortdoc "Revokes one installation API key by its public ID"
  @moduledoc "Run `mix vxpipe.operator_key.revoke --key-id PUBLIC_KEY_ID`. Does not expose key material."
  @requirements ["app.config"]
  @impl true
  def run(arguments) do
    id = OperatorKeyCLI.argument!(arguments, :key_id)
    CLI.ensure_ready!()
    revoked = Vxpipe.Calls.revoke_operator_api_key(id) |> CLI.unwrap!()
    CLI.output!(%{api_key_id: revoked.id, revoked_at: DateTime.to_iso8601(revoked.revoked_at)})
  end
end
