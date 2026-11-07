defmodule Vxpipe.Calls.Test.MCPResolvedTargetFixture do
  def resolve(%{"listing" => _} = input, entry) when is_map(entry) do
    {:ok,
     %{
       endpoint: entry["endpoint"],
       endpoint_identity: entry["endpoint"],
       directory_entry: entry,
       directory_id: entry["directory_id"] <> "/" <> entry["integration_id"],
       revision: input["revision"]
     }}
  end

  def resolve(input, _entry) do
    with {:ok, endpoint} <- Vxpipe.MCP.StaticConfiguration.endpoint(input["endpoint"]) do
      {:ok,
       %{
         endpoint: endpoint,
         endpoint_identity: endpoint,
         directory_id: nil,
         directory_entry: nil,
         revision: input["revision"]
       }}
    end
  end
end
