defmodule Vxpipe.CallEngine.RemoteMCP.ConfiguredNames do
  @moduledoc "Public integration names from configured records, without remote tool discovery."
  alias Vxpipe.CallEngine.RemoteMCP.{ApplicationConfiguration, ConfiguredIntegration}

  def list(tenant) do
    settings = Application.get_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, [])
    remote = Keyword.get(settings, :remote_mcp, [])
    {module, options} = Keyword.get(remote, :source, {ApplicationConfiguration, []})

    with {:ok, integrations} <- module.fetch(options),
         true <-
           is_list(integrations) and
             Enum.all?(integrations, &is_struct(&1, ConfiguredIntegration)) do
      names =
        integrations
        |> Enum.filter(&(&1.connection_key.scope in [:application, {:tenant, tenant}]))
        |> Enum.map(& &1.connection_key.integration_id)
        |> Enum.uniq()
        |> Enum.sort()

      {:ok, names}
    else
      _invalid -> {:error, :invalid_remote_mcp_configuration}
    end
  rescue
    _error -> {:error, :invalid_remote_mcp_configuration}
  catch
    :exit, _reason -> {:error, :invalid_remote_mcp_configuration}
  end
end
