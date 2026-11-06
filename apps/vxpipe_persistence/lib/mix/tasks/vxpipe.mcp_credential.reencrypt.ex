defmodule Mix.Tasks.Vxpipe.McpCredential.Reencrypt do
  use Mix.Task

  alias Vxpipe.Calls.Repositories
  alias Vxpipe.Persistence.CLI
  alias Vxpipe.Persistence.MCP.ConnectionStore

  @shortdoc "Re-encrypts one bounded MCP credential batch with the platform's active key"
  @requirements ["app.config"]

  @moduledoc """
  Re-encrypts stored tenant MCP credentials and OAuth grants without changing their values, identity or status.

  Use --batch-size 1..500 (default 100). Output contains processed counts, the current key ID
  and remaining counts by old key ID. Busy rows are skipped but remain in those counts;
  rerun until remaining_by_key is empty. A failed batch commits no updates.

  Supply keys through the existing platform keyring. Stage the new decrypt key on every
  reader, switch every writer to the new active key, then run batches. Retire the old key
  only after every writer has switched and no old-key rows remain in any credential
  store. Pending OAuth attempts also require the old key until claimed or expired. Run from a trusted
  platform operator session. This command accepts no secret flags or credential payload.
  """

  @impl true
  def run(arguments) do
    batch_size = batch_size!(arguments)
    CLI.ensure_ready!()

    context =
      case Repositories.fetch([], :mcp_connection_repository) do
        {:ok, {ConnectionStore, context}} when is_list(context) -> context
        _unconfigured -> Mix.raise("MCP credential storage is not configured")
      end

    context
    |> ConnectionStore.reencrypt(batch_size)
    |> CLI.unwrap!()
    |> CLI.output!()
  end

  defp batch_size!(arguments) do
    case OptionParser.parse(arguments, strict: [batch_size: :integer]) do
      {options, [], []} ->
        size = Keyword.get(options, :batch_size, 100)

        if size in 1..500,
          do: size,
          else: Mix.raise("batch size must be an integer from 1 to 500")

      _invalid ->
        Mix.raise("invalid re-encryption arguments; use only --batch-size 1..500")
    end
  end
end
