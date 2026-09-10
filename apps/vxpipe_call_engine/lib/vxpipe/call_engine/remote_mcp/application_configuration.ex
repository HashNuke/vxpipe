defmodule Vxpipe.CallEngine.RemoteMCP.ApplicationConfiguration do
  @moduledoc """
  Reads raw remote MCP integration records from OTP application configuration.

  The complete setting is rejected when any record is invalid. Private client settings are
  retained only inside redacted `ConfiguredIntegration` values.
  """

  @behaviour Vxpipe.CallEngine.RemoteMCP.ConfigurationSource

  alias Vxpipe.CallEngine.RemoteMCP.ConfiguredIntegration

  @default_application :vxpipe_call_engine
  @default_key :remote_mcp_integrations

  @impl true
  def fetch(options) when is_list(options) do
    with {:ok, options} <- Keyword.validate(options, [:application, :key]),
         application when is_atom(application) <-
           Keyword.get(options, :application, @default_application),
         key when is_atom(key) <- Keyword.get(options, :key, @default_key),
         configured when is_list(configured) <- Application.get_env(application, key, []),
         {:ok, integrations} <- build_integrations(configured) do
      {:ok, integrations}
    else
      _invalid -> {:error, :invalid_remote_mcp_configuration}
    end
  end

  def fetch(_options), do: {:error, :invalid_remote_mcp_configuration}

  defp build_integrations(configured) do
    configured
    |> Enum.reduce_while({:ok, []}, fn raw, {:ok, integrations} ->
      case ConfiguredIntegration.new(raw) do
        {:ok, integration} -> {:cont, {:ok, [integration | integrations]}}
        {:error, _reason} -> {:halt, {:error, :invalid_remote_mcp_configuration}}
      end
    end)
    |> case do
      {:ok, integrations} -> {:ok, Enum.reverse(integrations)}
      {:error, _reason} = error -> error
    end
  end
end
