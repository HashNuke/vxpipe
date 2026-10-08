defmodule Vxpipe.Calls.EffectiveServiceBindings do
  @moduledoc "Trusted effective provider inventory; external callers must authorize their scope."
  alias Vxpipe.Calls.{ProviderAuth, Repositories}

  @fields [
    :provider,
    :name,
    :source,
    :status,
    :credential_id,
    :platform_available,
    :saved_fields,
    :last_validated_at
  ]

  def list(scope, options) do
    with :ok <- ProviderAuth.owner(scope),
         {:ok, repository} <- Repositories.fetch(options, :provider_credential_repository),
         {:ok, %{tenant: tenant, bindings: bindings}} <-
           Repositories.call(repository, :list_bindings, [scope]),
         true <- valid_tenant?(tenant, scope),
         true <- is_list(bindings) and length(bindings) <= 1_500,
         true <- Enum.all?(bindings, &valid_binding?(&1, scope)),
         true <- Enum.uniq_by(bindings, &{&1.provider, &1.name}) == bindings do
      {:ok,
       %{
         tenant: if(tenant, do: Map.take(tenant, [:key, :name])),
         bindings: Enum.map(bindings, &Map.take(&1, @fields))
       }}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :service_directory_unavailable}
    end
  end

  defp valid_tenant?(nil, :platform), do: true
  defp valid_tenant?(tenant, {:tenant, key}), do: valid_tenant?(tenant, key)
  defp valid_tenant?(%{key: key, name: name}, key) when is_binary(name), do: true
  defp valid_tenant?(_tenant, _scope), do: false

  defp valid_binding?(
         %{
           provider: provider,
           name: name,
           source: source,
           status: status,
           credential_id: id,
           platform_available: available,
           saved_fields: fields,
           last_validated_at: validated
         },
         scope
       ) do
    sources = if scope == :platform, do: [:platform], else: [:platform, :tenant]

    ProviderAuth.binding(scope, provider, name) == :ok and source in sources and
      status in [:connected, :invalid, :unavailable] and
      optional_id?(id) and is_boolean(available) and
      is_list(fields) and
      Enum.all?(fields, &(&1 in ["api_key", "public_key", "account_sid", "auth_token"])) and
      (is_nil(validated) or is_struct(validated, DateTime))
  end

  defp valid_binding?(_binding, _scope), do: false
  defp optional_id?(nil), do: true
  defp optional_id?(id), do: is_binary(id) and byte_size(id) in 1..128
end
