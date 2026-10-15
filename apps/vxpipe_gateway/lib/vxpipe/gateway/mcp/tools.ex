defmodule Vxpipe.Gateway.MCP.Tools do
  @moduledoc "Static MCP tool routing; each group delegates policy and operations to its owning application."

  alias Vxpipe.Gateway.MCP.{CallSpecTools, CallTools, TenantTools}

  @groups [TenantTools, CallSpecTools, CallTools]

  def list(actor), do: Enum.flat_map(@groups, & &1.list(actor))

  def authorize(actor, name, arguments) do
    case group(name) do
      nil -> {:error, :invalid_tool_arguments}
      group -> group.authorize(actor, name, arguments)
    end
  end

  def call(actor, name, arguments, options), do: group(name).call(actor, name, arguments, options)
  def error(name, reason), do: group(name).error(name, reason)

  defp group(name), do: Enum.find(@groups, &(name in &1.names()))
end
