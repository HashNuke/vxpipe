defmodule Vxpipe.MCP.ReferenceProbe do
  @moduledoc """
  Exercises the pinned Everything-server `echo` operation through Vxpipe's public boundary.

  The returned tool definition and result preserve remote string-keyed data so this probe
  also detects accidental catalog rewriting.
  """

  alias Vxpipe.MCP.{Catalog, Discovery, ExMCPClient, Invocation}

  @message "vxpipe-reference-probe"
  @deadline_ms 5_000
  @max_decoded_bytes 262_144

  @spec run(term(), keyword()) ::
          {:ok, %{tool: map(), result: map()}} | {:error, Discovery.error() | Invocation.error()}
  def run(client, opts \\ []) do
    protocol = Keyword.get(opts, :protocol, ExMCPClient)

    with {:ok, catalog} <-
           Discovery.discover(client,
             protocol: protocol,
             deadline_ms: @deadline_ms,
             max_pages: 20,
             max_decoded_bytes: @max_decoded_bytes
           ),
         {:ok, tool} <- Catalog.fetch(catalog, "echo"),
         {:ok, result} <-
           Invocation.call(
             client,
             catalog,
             "echo",
             %{"message" => @message},
             protocol: protocol,
             deadline_ms: @deadline_ms,
             max_result_bytes: @max_decoded_bytes
           ) do
      {:ok, %{tool: tool, result: result}}
    end
  end
end
