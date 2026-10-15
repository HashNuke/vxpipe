defmodule Vxpipe.Gateway.MCP.TenantTools do
  @moduledoc "Tenant discovery tools over the shared Calls directory operations."

  alias Vxpipe.Calls
  alias Vxpipe.Gateway.TenantJSON

  @tools [
    %{
      name: "list_tenants",
      description: "List tenants visible to this credential, with bounded pagination.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{
          page: %{type: "integer", minimum: 1, maximum: 2_147_483_647, default: 1},
          page_size: %{type: "integer", minimum: 1, maximum: 50, default: 25}
        }
      },
      annotations: %{
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false
      }
    },
    %{
      name: "get_tenant",
      description: "Get public information about one tenant visible to this credential.",
      inputSchema: %{
        type: "object",
        additionalProperties: false,
        properties: %{tenant_key: %{type: "string", pattern: "^[A-Za-z0-9_-]{16}$"}},
        required: ["tenant_key"]
      },
      annotations: %{
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false
      }
    }
  ]

  def list(actor) do
    if Calls.authorize_tenant_discovery(actor) == :ok, do: @tools, else: []
  end

  def authorize(actor, name, arguments) do
    with {:ok, arguments} <- validate(name, arguments),
         :ok <- Calls.authorize_tenant_discovery(actor) do
      {:ok, arguments}
    end
  end

  def call(actor, "list_tenants", arguments, options) do
    paging = [page: arguments["page"], limit: arguments["page_size"]]

    with {:ok, page} <- Calls.search_operator_tenants(actor, paging ++ options),
         do: {:ok, TenantJSON.page(page)}
  end

  def call(actor, "get_tenant", arguments, options) do
    with {:ok, tenant} <- Calls.fetch_visible_tenant(actor, arguments["tenant_key"], options),
         do: {:ok, TenantJSON.tenant(tenant)}
  end

  defp validate(name, arguments) when is_map(arguments) do
    case Enum.find(@tools, &(&1.name == name)) do
      nil ->
        {:error, :invalid_tool_arguments}

      tool ->
        case ExMCP.Server.Tools.Helpers.validate_arguments(arguments, tool.inputSchema) do
          {:ok, validated} -> {:ok, validated}
          {:error, _details} -> {:error, :invalid_tool_arguments}
        end
    end
  end

  defp validate(_name, _arguments), do: {:error, :invalid_tool_arguments}
end
