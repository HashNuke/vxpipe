defmodule Vxpipe.CallEngine.RemoteMCP.CatalogRefreshCycle do
  @moduledoc """
  Runs one configuration-source fetch and all-or-nothing catalog refresh.

  Source and discovery failures are normalized before returning to the lifecycle owner so private
  adapter errors never become process state or public status.
  """

  alias Vxpipe.CallEngine.RemoteMCP.CatalogRefresh

  @type outcome :: :ok | {:error, :catalog_refresh_failed | :configuration_unavailable}

  @spec run({module(), keyword()}, keyword()) :: outcome()
  def run({source_module, source_options}, refresh_options) do
    case source_module.fetch(source_options) do
      {:ok, configured} -> refresh(configured, refresh_options)
      {:error, _reason} -> {:error, :configuration_unavailable}
      _invalid -> {:error, :configuration_unavailable}
    end
  rescue
    _exception -> {:error, :configuration_unavailable}
  catch
    :exit, _reason -> {:error, :configuration_unavailable}
  end

  defp refresh(configured, options) do
    case CatalogRefresh.run(configured, options) do
      {:ok, _snapshot} -> :ok
      {:error, _reason} -> {:error, :catalog_refresh_failed}
    end
  end
end
