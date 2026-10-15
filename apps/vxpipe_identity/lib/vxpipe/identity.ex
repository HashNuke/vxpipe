defmodule Vxpipe.Identity do
  @moduledoc """
  Named-user identity and authorization through transport-independent domain operations.

  Pure domain plus repository ports. Ecto/PostgreSQL adapters live in
  `vxpipe_persistence`; transports resolve the configured ports through this boundary.
  """

  @doc """
  Resolves the repository ports configured for Identity operations.

  Runtime composition supplies the map under `:vxpipe_identity, :dependencies`.
  Identity does not depend on a particular persistence adapter or HTTP host.
  An unconfigured installation fails closed instead of using a transport's defaults.
  """
  @spec dependencies() :: {:ok, map()} | {:error, :unavailable}
  def dependencies do
    case Application.get_env(:vxpipe_identity, :dependencies) do
      dependencies when is_map(dependencies) -> {:ok, dependencies}
      _ -> {:error, :unavailable}
    end
  end
end
