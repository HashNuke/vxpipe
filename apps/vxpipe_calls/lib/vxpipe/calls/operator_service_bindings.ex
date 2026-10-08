defmodule Vxpipe.Calls.OperatorServiceBindings do
  @moduledoc "Installation-authorized effective provider inventory."
  alias Vxpipe.Calls.{EffectiveServiceBindings, InstallationOperator}

  def list(%InstallationOperator{grant: :installation_operator}, scope, options) do
    with {:ok, directory} <- EffectiveServiceBindings.list(scope, options) do
      {:ok, Map.put(directory, :model_catalog, Vxpipe.CallEngine.ModelCatalog.catalog())}
    end
  end

  def list(_authority, _scope, _options), do: {:error, :installation_operator_required}
end
