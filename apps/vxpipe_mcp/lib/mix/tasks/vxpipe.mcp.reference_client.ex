defmodule Mix.Tasks.Vxpipe.Mcp.ReferenceClient do
  @shortdoc "Calls the pinned MCP Everything reference fixture"

  @moduledoc """
  Discovers and calls the `echo` tool on an isolated Everything reference server.

      mix vxpipe.mcp.reference_client http://localhost:4321/mcp

  Plaintext URLs are accepted only through Vxpipe's loopback fixture boundary.
  """

  use Mix.Task

  alias Vxpipe.MCP.ReferenceClient

  @impl Mix.Task
  def run([server_url]) do
    ensure_mcp_started!()

    case ReferenceClient.run(server_url) do
      {:ok, evidence} -> Mix.shell().info(Jason.encode!(evidence))
      {:error, reason} -> Mix.raise("MCP reference client failed: #{inspect(reason)}")
    end
  end

  def run(_args), do: Mix.raise("expected one reference server URL")

  defp ensure_mcp_started! do
    case Application.ensure_all_started(:vxpipe_mcp) do
      {:ok, _applications} -> :ok
      {:error, _reason} -> Mix.raise("could not start the Vxpipe MCP application")
    end
  end
end
