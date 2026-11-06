defmodule Vxpipe.Console.MCPConnectionProbe do
  @moduledoc "Validates non-interactive connection input and MCP discovery for the Calls management port."
  @behaviour Vxpipe.Calls.MCPConnectionProbe
  alias Vxpipe.MCP.{ConnectionCheck, StaticConfiguration}

  @impl true
  def check(options, tenant, %{"auth_method" => "own_client"} = input),
    do: Vxpipe.Console.MCPOAuthMachineConnection.check(options, tenant, input)

  def check(options, tenant, input) do
    check = Keyword.get(options, :connection_check, &ConnectionCheck.run(&1, &2, options))

    with {:ok, configuration} <- StaticConfiguration.new(input),
         {:ok, discovered} <- check.(tenant, configuration) do
      {:ok,
       %Vxpipe.Calls.ResolvedMCPConnection{
         connection: %{
           endpoint: configuration.endpoint,
           endpoint_identity: configuration.endpoint,
           auth_method: configuration.auth_method,
           server_name: discovered.server_name,
           catalog: discovered.catalog,
           directory_id: nil
         },
         secrets: configuration.secrets
       }}
    end
  end
end
