defmodule Vxpipe.Calls.ProviderCatalogErrors do
  @moduledoc "Value-free public failures shared by provider catalog transports."

  def response(:invalid_api_key), do: {401, %{code: "invalid_api_key"}}
  def response(:invalid_capability), do: {422, %{code: "invalid_capability"}}
  def response(:invalid_tenant_key), do: {400, %{code: "invalid_tenant_key"}}
  def response(:tenant_not_found), do: {404, %{code: "tenant_not_found"}}

  def response(reason)
      when reason in [
             :unsupported_provider,
             :unsupported_provider_capability,
             :provider_implementation_unavailable
           ],
      do: {404, %{code: "provider_not_found"}}

  def response(reason)
      when reason in [
             :insufficient_scope,
             :tenant_access_forbidden,
             :authoring_authority_required
           ],
      do: {403, %{code: "authoring_forbidden"}}

  def response(_reason), do: {503, %{code: "provider_catalog_unavailable"}}
end
