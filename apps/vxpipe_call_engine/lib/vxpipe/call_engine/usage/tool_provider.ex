defmodule Vxpipe.CallEngine.Usage.ToolProvider do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.InvocationBinding
  alias Vxpipe.CallEngine.Usage.ProviderContext

  @spec from_binding(InvocationBinding.t()) ::
          {:ok, ProviderContext.t()} | {:error, :invalid_provider_context}
  def from_binding(%InvocationBinding{handler: {:host, _action}}) do
    ProviderContext.new(name: "host_application")
  end

  def from_binding(%InvocationBinding{
        handler: {:remote_mcp, _owner},
        usage_integration_id: integration_id
      }) do
    ProviderContext.new(name: "remote_mcp", integration_id: integration_id)
  end

  def from_binding(%InvocationBinding{handler: {:platform, _action}}) do
    ProviderContext.new(name: "vxpipe")
  end

  def from_binding(%InvocationBinding{handler: {:participant_transfer, _binding}}) do
    ProviderContext.new(name: "vxpipe")
  end

  def from_binding(%InvocationBinding{handler: {:call_variables, _binding}}) do
    ProviderContext.new(name: "vxpipe")
  end

  def from_binding(%InvocationBinding{}), do: {:error, :invalid_provider_context}
end
