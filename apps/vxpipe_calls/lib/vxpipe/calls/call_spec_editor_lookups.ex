defmodule Vxpipe.Calls.CallSpecEditorLookups do
  @moduledoc "Installation-authorized, secret-free choices for the portable call spec editor."
  alias Vxpipe.CallEngine.RemoteMCP.ConfiguredNames

  alias Vxpipe.Calls.{
    EffectiveServiceBindings,
    InstallationOperator,
    OperatorAdministration,
    OperatorTelephonyApplications
  }

  def list(%InstallationOperator{grant: :installation_operator} = authority, tenant, options) do
    with {:ok, bindings} <- EffectiveServiceBindings.list(tenant, options),
         {:ok, telephony} <- OperatorAdministration.list_services(authority, tenant, options),
         {:ok, applications} <- OperatorTelephonyApplications.list(authority, tenant, options),
         {:ok, integrations} <- ConfiguredNames.list(tenant) do
      names =
        bindings.bindings
        |> Enum.group_by(& &1.provider, & &1.name)
        |> Map.new(fn {provider, names} -> {provider, Enum.sort(names)} end)

      {:ok,
       %{
         tenant: bindings.tenant,
         credential_names: names,
         telephony_services:
           (Enum.map(telephony.telephony_services, &%{key: &1.name, name: &1.name, provider: &1.provider}) ++
              Enum.map(applications.applications, &%{key: &1.name, name: &1.name, provider: "telnyx"}))
           |> Enum.uniq_by(& &1.key)
           |> Enum.sort_by(& &1.name),
         mcp_integrations: integrations,
         truncated: telephony.truncated or applications.truncated
       }}
    end
  end

  def list(_authority, _tenant, _options), do: {:error, :installation_operator_required}
end
