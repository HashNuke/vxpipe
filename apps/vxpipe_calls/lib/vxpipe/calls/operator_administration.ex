defmodule Vxpipe.Calls.OperatorAdministration do
  @moduledoc "Installation-wide, bounded read workflows for the operator application."

  alias Vxpipe.Calls.{
    CallDirectoryPage,
    CallDirectorySummary,
    DefinitionPage,
    InstallationOperator,
    OperatorCallContext,
    ProviderAuth,
    ProviderCredential,
    ProviderCredentialHints,
    PublicId,
    Repositories,
    ServiceDirectory,
    TelephonyService,
    Tenant,
    TenantPage
  }

  @default_page_size 25
  @maximum_page_size 100

  @spec list_tenants(InstallationOperator.t(), keyword()) ::
          {:ok, TenantPage.t()} | {:error, term()}
  def list_tenants(%InstallationOperator{grant: :installation_operator}, options)
      when is_list(options) do
    with {:ok, page} <- positive_integer(options, :page, 1),
         {:ok, limit} <- page_size(options),
         {:ok, repository} <- Repositories.fetch(options, :admin_repository),
         offset = (page - 1) * limit,
         {:ok, {tenants, total}} <-
           Repositories.call(repository, :list_tenants, [limit, offset]),
         {:ok, total_pages} <- page_range(page, total, limit) do
      {:ok,
       %TenantPage{
         tenants: tenants,
         page: page,
         page_size: limit,
         total: total,
         total_pages: total_pages
       }}
    end
  end

  def list_tenants(%InstallationOperator{}, _options),
    do: {:error, :installation_operator_required}

  def list_tenants(_authority, _options), do: {:error, :installation_operator_required}

  @spec list_definitions(InstallationOperator.t(), String.t(), keyword()) ::
          {:ok, DefinitionPage.t()} | {:error, term()}
  def list_definitions(
        %InstallationOperator{grant: :installation_operator},
        tenant_key,
        options
      )
      when is_binary(tenant_key) and byte_size(tenant_key) > 0 and is_list(options) do
    with {:ok, page} <- positive_integer(options, :page, 1),
         {:ok, limit} <- page_size(options),
         {:ok, repository} <- Repositories.fetch(options, :admin_repository),
         offset = (page - 1) * limit,
         {:ok, {tenant, definitions, total}} <-
           Repositories.call(repository, :list_definitions, [tenant_key, limit, offset]),
         {:ok, total_pages} <- page_range(page, total, limit, :definition_page_out_of_range) do
      {:ok,
       %DefinitionPage{
         tenant: tenant,
         definitions: definitions,
         page: page,
         page_size: limit,
         total: total,
         total_pages: total_pages
       }}
    end
  end

  def list_definitions(%InstallationOperator{}, _tenant_key, _options),
    do: {:error, :installation_operator_required}

  def list_definitions(_authority, _tenant_key, _options),
    do: {:error, :installation_operator_required}

  @spec list_calls(InstallationOperator.t(), String.t(), keyword()) ::
          {:ok, CallDirectoryPage.t()} | {:error, term()}
  def list_calls(
        %InstallationOperator{grant: :installation_operator},
        tenant_key,
        options
      )
      when is_binary(tenant_key) and byte_size(tenant_key) > 0 and is_list(options) do
    with {:ok, definition_id} <- definition_filter(options),
         {:ok, page} <- positive_integer(options, :page, 1),
         {:ok, limit} <- page_size(options),
         {:ok, repository} <- Repositories.fetch(options, :admin_repository),
         offset = (page - 1) * limit,
         {:ok, {tenant, definitions, definitions_truncated, calls, total}} <-
           Repositories.call(repository, :list_calls, [
             tenant_key,
             definition_id,
             limit,
             offset
           ]),
         {:ok, total_pages} <- page_range(page, total, limit, :call_page_out_of_range) do
      {:ok,
       %CallDirectoryPage{
         tenant: tenant,
         definitions: definitions,
         definitions_truncated: definitions_truncated,
         selected_definition_id: definition_id,
         calls: calls,
         page: page,
         page_size: limit,
         total: total,
         total_pages: total_pages
       }}
    end
  end

  def list_calls(%InstallationOperator{}, _tenant_key, _options),
    do: {:error, :installation_operator_required}

  def list_calls(_authority, _tenant_key, _options),
    do: {:error, :installation_operator_required}

  @spec fetch_call_context(InstallationOperator.t(), String.t(), String.t(), keyword()) ::
          {:ok, OperatorCallContext.t()} | {:error, term()}
  def fetch_call_context(
        %InstallationOperator{grant: :installation_operator},
        tenant_key,
        call_id,
        options
      )
      when is_binary(tenant_key) and byte_size(tenant_key) > 0 and is_binary(call_id) and
             byte_size(call_id) > 0 and byte_size(call_id) <= 256 and is_list(options) do
    with {:ok, repository} <- Repositories.fetch(options, :admin_repository),
         {:ok, {%Tenant{key: ^tenant_key} = tenant, %CallDirectorySummary{id: ^call_id} = call}} <-
           Repositories.call(repository, :fetch_call_context, [tenant_key, call_id]) do
      {:ok, %OperatorCallContext{tenant: tenant, call: call}}
    else
      {:ok, _invalid} -> {:error, :call_directory_unavailable}
      error -> error
    end
  end

  def fetch_call_context(%InstallationOperator{}, _tenant_key, _call_id, _options),
    do: {:error, :installation_operator_required}

  def fetch_call_context(_authority, _tenant_key, _call_id, _options),
    do: {:error, :installation_operator_required}

  @spec list_services(InstallationOperator.t(), String.t(), keyword()) ::
          {:ok, ServiceDirectory.t()} | {:error, term()}
  def list_services(
        %InstallationOperator{grant: :installation_operator},
        tenant_key,
        options
      )
      when is_binary(tenant_key) and byte_size(tenant_key) > 0 and is_list(options) do
    with {:ok, repository} <- Repositories.fetch(options, :admin_repository),
         {:ok, {tenant, credentials, telephony_services, truncated}} <-
           Repositories.call(repository, :list_services, [tenant_key]),
         true <- is_boolean(truncated),
         :ok <- validate_service_directory(tenant_key, tenant, credentials, telephony_services) do
      {:ok,
       %ServiceDirectory{
         tenant: tenant,
         credentials: credentials,
         telephony_services: telephony_services,
         truncated: truncated
       }}
    else
      false -> {:error, :service_directory_unavailable}
      error -> error
    end
  end

  def list_services(%InstallationOperator{}, _tenant_key, _options),
    do: {:error, :installation_operator_required}

  def list_services(_authority, _tenant_key, _options),
    do: {:error, :installation_operator_required}

  @spec create_credential(
          InstallationOperator.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          map(),
          keyword()
        ) :: {:ok, ProviderCredential.t()} | {:error, term()}
  def create_credential(
        %InstallationOperator{grant: :installation_operator},
        tenant_key,
        provider,
        name,
        auth_kind,
        payload,
        options
      )
      when is_list(options) do
    with :ok <- ProviderAuth.binding(tenant_key, provider, name),
         :ok <- ProviderAuth.validate(provider, auth_kind, payload),
         {:ok, repository} <- Repositories.fetch(options, :provider_credential_repository) do
      credential = %ProviderCredential{
        id: generate_uuid(options),
        tenant_key: tenant_key,
        provider: provider,
        name: name,
        auth_kind: auth_kind,
        secret_hints: ProviderCredentialHints.from_payload(auth_kind, payload)
      }

      repository
      |> Repositories.call(:provision, [credential, payload])
      |> validate_created_credential(credential)
    end
  end

  def create_credential(
        %InstallationOperator{},
        _tenant,
        _provider,
        _name,
        _kind,
        _payload,
        _opts
      ),
      do: {:error, :installation_operator_required}

  def create_credential(_authority, _tenant, _provider, _name, _kind, _payload, _options),
    do: {:error, :installation_operator_required}

  @spec update_credential(
          InstallationOperator.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          map(),
          keyword()
        ) :: {:ok, ProviderCredential.t()} | {:error, term()}
  def update_credential(
        %InstallationOperator{grant: :installation_operator},
        tenant_key,
        credential_id,
        provider,
        auth_kind,
        payload,
        options
      )
      when is_binary(credential_id) and byte_size(credential_id) in 1..128 and is_list(options) do
    with :ok <- ProviderAuth.binding(tenant_key, provider, provider),
         :ok <- ProviderAuth.validate(provider, auth_kind, payload),
         {:ok, repository} <- Repositories.fetch(options, :provider_credential_repository) do
      repository
      |> Repositories.call(:replace, [
        tenant_key,
        credential_id,
        provider,
        auth_kind,
        payload,
        ProviderCredentialHints.from_payload(auth_kind, payload)
      ])
      |> validate_updated_credential(tenant_key, credential_id, provider, auth_kind)
    end
  end

  def update_credential(%InstallationOperator{}, _tenant, _id, _provider, _kind, _payload, _opts),
    do: {:error, :installation_operator_required}

  def update_credential(_authority, _tenant, _id, _provider, _kind, _payload, _options),
    do: {:error, :installation_operator_required}

  defp generate_uuid(options) do
    options
    |> Keyword.get(:uuid_generator, &PublicId.uuid/0)
    |> then(fn generator -> generator.() end)
  end

  defp validate_service_directory(
         tenant_key,
         %Tenant{key: tenant_key},
         credentials,
         telephony_services
       )
       when is_list(credentials) and is_list(telephony_services) do
    credential_ids =
      credentials
      |> Enum.filter(&valid_credential_metadata?(&1, tenant_key))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    credentials_valid? = MapSet.size(credential_ids) == length(credentials)

    services_valid? =
      Enum.all?(telephony_services, fn
        %TelephonyService{tenant_key: ^tenant_key, provider: provider, credential_id: id}
        when provider in ["telnyx", "twilio"] ->
          MapSet.member?(credential_ids, id)

        _invalid ->
          false
      end)

    if credentials_valid? and services_valid?,
      do: :ok,
      else: {:error, :service_directory_unavailable}
  end

  defp validate_service_directory(_tenant_key, _tenant, _credentials, _services),
    do: {:error, :service_directory_unavailable}

  defp valid_credential_metadata?(
         %ProviderCredential{
           tenant_key: tenant_key,
           provider: provider,
           name: name,
           auth_kind: auth_kind
         },
         tenant_key
       ) do
    ProviderAuth.binding(tenant_key, provider, name) == :ok and
      valid_auth_kind?(provider, auth_kind)
  end

  defp valid_credential_metadata?(_credential, _tenant_key), do: false

  defp valid_auth_kind?("twilio", "account_sid_auth_token"), do: true

  defp valid_auth_kind?(provider, "api_key")
       when provider in ["google", "deepgram", "zenmux", "telnyx"],
       do: true

  defp valid_auth_kind?(_provider, _auth_kind), do: false

  defp validate_created_credential(
         {:ok,
          %ProviderCredential{
            tenant_key: tenant_key,
            provider: provider,
            name: name,
            auth_kind: auth_kind
          } = stored},
         %ProviderCredential{
           tenant_key: tenant_key,
           provider: provider,
           name: name,
           auth_kind: auth_kind
         }
       ),
       do: {:ok, stored}

  defp validate_created_credential({:ok, _invalid}, _requested),
    do: {:error, :provider_credential_write_failed}

  defp validate_created_credential({:error, _reason} = error, _requested), do: error

  defp validate_updated_credential(
         {:ok,
          %ProviderCredential{
            id: credential_id,
            tenant_key: tenant_key,
            provider: provider,
            auth_kind: auth_kind
          } = stored},
         tenant_key,
         credential_id,
         provider,
         auth_kind
       ),
       do: {:ok, stored}

  defp validate_updated_credential({:ok, _invalid}, _tenant, _id, _provider, _kind),
    do: {:error, :provider_credential_write_failed}

  defp validate_updated_credential({:error, _reason} = error, _tenant, _id, _provider, _kind),
    do: error

  defp page_size(options) do
    with {:ok, limit} <- positive_integer(options, :limit, @default_page_size),
         true <- limit <= @maximum_page_size do
      {:ok, limit}
    else
      _invalid -> {:error, :invalid_tenant_page_request}
    end
  end

  defp positive_integer(options, key, default) do
    case Keyword.get(options, key, default) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _invalid -> {:error, :invalid_tenant_page_request}
    end
  end

  defp definition_filter(options) do
    case Keyword.get(options, :definition_id) do
      nil ->
        {:ok, nil}

      value when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 256 ->
        {:ok, value}

      _invalid ->
        {:error, :invalid_call_directory_request}
    end
  end

  defp total_pages(0, _limit), do: 0
  defp total_pages(total, limit), do: div(total + limit - 1, limit)

  defp page_range(page, total, limit, error \\ :tenant_page_out_of_range) do
    pages = total_pages(total, limit)

    if page <= max(pages, 1),
      do: {:ok, pages},
      else: {:error, error}
  end
end
