defmodule Vxpipe.Calls.CallSpecEditorLookups do
  @moduledoc "Installation-authorized, secret-free choices for the portable call spec editor."
  alias Vxpipe.CallEngine.RemoteMCP.ConfiguredNames

  alias Vxpipe.Calls.{
    EffectiveServiceBindings,
    InstallationOperator,
    OperatorTelephonyApplications
  }

  def list(%InstallationOperator{grant: :installation_operator} = authority, tenant, options) do
    with {:ok, bindings} <- EffectiveServiceBindings.list(tenant, options),
         {:ok, telephony} <- OperatorTelephonyApplications.list(authority, tenant, options),
         {:ok, integrations} <- ConfiguredNames.list(tenant) do
      names =
        bindings.bindings
        |> Enum.group_by(& &1.provider, & &1.name)
        |> Map.new(fn {provider, names} -> {provider, Enum.sort(names)} end)

      {:ok,
       %{
         tenant: bindings.tenant,
         credential_names: names,
         telephony_services: Enum.map(telephony.applications, &%{key: &1.name, name: &1.name}),
         mcp_integrations: integrations,
         truncated: telephony.truncated
       }}
    end
  end

  def list(_authority, _tenant, _options), do: {:error, :installation_operator_required}
end
