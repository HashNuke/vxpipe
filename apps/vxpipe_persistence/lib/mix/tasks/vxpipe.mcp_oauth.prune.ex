defmodule Mix.Tasks.Vxpipe.McpOauth.Prune do
  use Mix.Task

  alias Vxpipe.Calls.Repositories
  alias Vxpipe.Persistence.CLI
  alias Vxpipe.Persistence.MCP.OAuthAttemptStore

  @shortdoc "Deletes one bounded batch of expired or claimed outbound MCP OAuth attempts"
  @requirements ["app.config"]
  @moduledoc """
  Deletes terminal outbound MCP OAuth attempts without decrypting their payloads.

  Use --batch-size 1..500 (default 100). Output contains processed and remaining
  terminal-row counts plus pending_by_key counts for live unclaimed attempts.
  Locked rows are skipped; repeat until remaining is zero. Pending attempts remain
  usable. No authorization state, session, tenant, URL or secret is printed.

  Run periodically from a trusted operator scheduler. Before retiring a key, switch
  all writers, complete provider/MCP credential rotation and verify no live attempts
  still depend on that key. This command's counts alone do not cover other stores.
  """

  @impl true
  def run(arguments) do
    size = batch_size!(arguments)
    CLI.ensure_ready!()

    context =
      case Repositories.fetch([], :mcp_oauth_attempt_repository) do
        {:ok, {OAuthAttemptStore, context}} when is_list(context) -> context
        _ -> Mix.raise("OAuth attempt storage is not configured")
      end

    context |> OAuthAttemptStore.prune(size) |> CLI.unwrap!() |> CLI.output!()
  end

  defp batch_size!(arguments) do
    case OptionParser.parse(arguments, strict: [batch_size: :integer]) do
      {options, [], []} ->
        size = Keyword.get(options, :batch_size, 100)

        if size in 1..500,
          do: size,
          else: Mix.raise("batch size must be an integer from 1 to 500")

      _ ->
        Mix.raise("invalid pruning arguments; use only --batch-size 1..500")
    end
  end
end
