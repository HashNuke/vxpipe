defmodule Vxpipe.CallEngine.CredentialSource do
  @moduledoc "Host-injected tenant authentication boundary, invoked in capability preparation workers."

  alias Vxpipe.CallEngine.{CapabilityCatalog, ProviderCredential}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection

  @callback resolve(term(), String.t(), String.t(), String.t()) ::
              {:ok, ProviderCredential.t()} | {:error, atom()}

  def resolve(tenant_id, %CapabilitySelection{} = selection, options) do
    if CapabilityCatalog.credential_required?(selection) do
      with {:ok, credential} <-
             resolve_private(tenant_id, selection, Keyword.get(options, :credential_source)),
           true <-
             selected_binding?(credential, selection, Keyword.get(options, :credential_bindings)) do
        {:ok, credential}
      else
        _unavailable -> {:error, :provider_credential_unavailable}
      end
    else
      {:ok, nil}
    end
  end

  defp selected_binding?(_credential, _selection, nil), do: true

  defp selected_binding?(credential, selection, bindings) when is_map(bindings) do
    Map.get(bindings, {selection.provider, selection.credential_name}) ==
      ProviderCredential.binding_identity(credential)
  end

  defp selected_binding?(_credential, _selection, _bindings), do: false

  defp resolve_private(tenant_id, selection, {module, context}) when is_atom(module) do
    with {:ok, %ProviderCredential{} = credential} <-
           module.resolve(context, tenant_id, selection.provider, selection.credential_name),
         true <- credential.tenant_id == tenant_id and credential.provider == selection.provider,
         true <- credential.owner in [nil, :platform, {:tenant, tenant_id}],
         true <- credential.name == selection.credential_name,
         true <- is_binary(credential.id) and byte_size(credential.id) > 0,
         true <- is_integer(credential.version) and credential.version > 0,
         true <- is_map(credential.payload) do
      {:ok, credential}
    else
      _unavailable -> {:error, :provider_credential_unavailable}
    end
  rescue
    _exception -> {:error, :provider_credential_unavailable}
  catch
    :exit, _reason -> {:error, :provider_credential_unavailable}
  end

  defp resolve_private(_tenant_id, _selection, _source),
    do: {:error, :provider_credential_unavailable}
end
