defmodule Mix.Tasks.Vxpipe.Mcp.ConformanceClient do
  @shortdoc "Runs one official MCP client-conformance scenario"

  @moduledoc """
  Runs the Vxpipe MCP client against a server URL supplied by the official conformance
  harness. The scenario is read from `MCP_CONFORMANCE_SCENARIO`.

      mix vxpipe.mcp.conformance_client http://localhost:4321/mcp

  Only the pinned, in-scope `initialize` and `tools_call` scenarios are supported.
  """

  use Mix.Task

  alias Vxpipe.MCP.ConformanceClient

  @impl Mix.Task
  def run([server_url]) do
    ensure_mcp_started!()
    scenario = System.get_env("MCP_CONFORMANCE_SCENARIO", "")

    case ConformanceClient.run(server_url, scenario) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("MCP conformance client failed: #{inspect(reason)}")
    end
  end

  def run(_args), do: Mix.raise("expected one conformance server URL")

  defp ensure_mcp_started! do
    case Application.ensure_all_started(:vxpipe_mcp) do
      {:ok, _applications} -> :ok
      {:error, _reason} -> Mix.raise("could not start the Vxpipe MCP application")
    end
  end
end
