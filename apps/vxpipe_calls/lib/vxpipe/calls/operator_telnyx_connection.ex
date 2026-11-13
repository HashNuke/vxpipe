defmodule Vxpipe.Calls.OperatorTelnyxConnection do
  @moduledoc "Authorized, atomic editing of Telnyx credentials and application configuration."

  alias Vxpipe.Calls.{
    InstallationOperator,
    OperatorAdministration,
    OperatorServiceBindings,
    OperatorTelephonyApplications,
    ProviderAuth,
    ProviderCredentials,
    Repositories,
    TelephonyService,
    TelephonyServices,
    UserAuthorization
  }

  alias Vxpipe.Identity.Principal

  def get(authority, scope, options \\ [])

  def get(authority, {:tenant, tenant}, options), do: get(authority, tenant, options)

  def get(authority, scope, options) do
    with {:ok, directory} <- OperatorServiceBindings.list(authority, scope, options),
         {:ok, application_id} <- TelephonyServices.platform_application(options),
         {:ok, applications} <- applications(authority, scope, options) do
      {:ok,
       %{
         platform_application_id: application_id,
         credential:
           Enum.find(directory.bindings, &(&1.provider == "telnyx" and &1.name == "telnyx")),
         applications:
           Enum.map(applications, fn application ->
             Map.merge(application, %{
               effective_application_id: application.provider_connection_id || application_id,
               source: if(application.provider_connection_id, do: :tenant, else: :platform)
             })
           end)
       }}
    end
  end

  def update(authority, scope, attributes, options \\ [])

  def update(authority, {:tenant, tenant}, attributes, options),
    do: update(authority, tenant, attributes, options)

  def update(authority, scope, attributes, options) do
    with :ok <- ProviderAuth.owner(scope),
         :ok <- input(attributes),
         :ok <- authorize_changes(authority, scope, attributes),
         {:ok, current} <- get(authority, scope, options),
         :ok <- application_input(scope, attributes, current),
         {:ok, repository} <- Repositories.fetch(options, :telephony_service_repository) do
      Repositories.call(repository, :with_configuration, [
        scope,
        fn ->
          with :ok <- save_credentials(authority, scope, attributes, options),
               :ok <- save_application(authority, scope, attributes, options),
               {:ok, saved} <- get(authority, scope, options),
               :ok <- valid_pairing(saved) do
            {:ok, saved}
          end
        end
      ])
    end
  end

  defp valid_pairing(%{credential: %{source: :tenant}, applications: applications}) do
    if Enum.any?(applications, &is_nil(&1.provider_connection_id)),
      do: {:error, :telnyx_application_required},
      else: :ok
  end

  defp valid_pairing(_connection), do: :ok

  defp input(attributes) when is_map(attributes) and map_size(attributes) > 0 do
    if Enum.all?(Map.keys(attributes), &(&1 in ["application_id", "service_id", "credentials"])) and
         (Map.has_key?(attributes, "application_id") or Map.has_key?(attributes, "credentials")) and
         valid_selection?(attributes),
       do: :ok,
       else: {:error, :invalid_telephony_service}
  end

  defp input(_attributes), do: {:error, :invalid_telephony_service}

  defp valid_selection?(%{"service_id" => id} = attributes),
    do: is_binary(id) and Map.has_key?(attributes, "application_id")

  defp valid_selection?(_attributes), do: true

  defp application_input(:platform, _attributes, _current), do: :ok

  defp application_input(_tenant, %{"credentials" => values} = attributes, current)
       when is_map(values) do
    id = Map.get(attributes, "application_id")

    if TelephonyService.application_id?(id) and id != current.platform_application_id,
      do: :ok,
      else: {:error, :telnyx_application_required}
  end

  defp application_input(_tenant, _attributes, _current), do: :ok

  defp authorize_changes(%InstallationOperator{grant: :installation_operator}, _scope, _attrs),
    do: :ok

  defp authorize_changes(%Principal{} = principal, scope, attributes) do
    with :ok <- authorize_credentials(principal, scope, attributes) do
      case {scope, Map.has_key?(attributes, "application_id")} do
        {_, false} ->
          :ok

        {:platform, true} ->
          UserAuthorization.authorize_installation(principal, "platform_services.write")

        {tenant, true} ->
          UserAuthorization.authorize_tenant_service_write(principal, tenant)
      end
    end
  end

  defp authorize_changes(_authority, _scope, _attributes),
    do: {:error, :installation_operator_required}

  defp authorize_credentials(principal, scope, attributes) do
    if Map.has_key?(attributes, "credentials"),
      do: UserAuthorization.authorize_credential_write(principal, scope),
      else: :ok
  end

  defp applications(_authority, :platform, _options), do: {:ok, []}

  defp applications(authority, tenant, options) do
    case OperatorTelephonyApplications.list(authority, tenant, options) do
      {:ok, %{truncated: false, applications: applications}} -> {:ok, applications}
      {:ok, %{truncated: true}} -> {:error, :telephony_services_unavailable}
      error -> error
    end
  end

  defp save_credentials(authority, scope, %{"credentials" => values}, options) do
    with {:ok, credentials} <- ProviderCredentials.list(scope, options) do
      existing = Enum.find(credentials, &(&1.provider == "telnyx" and &1.name == "telnyx"))
      write_credentials(authority, scope, existing, values, options) |> saved()
    end
  end

  defp save_credentials(_authority, _scope, _attributes, _options), do: :ok

  defp write_credentials(_authority, _scope, nil, nil, _options), do: :ok

  defp write_credentials(authority, scope, credential, nil, options),
    do: OperatorAdministration.delete_credential(authority, scope, credential.id, options)

  defp write_credentials(authority, scope, nil, values, options) when is_map(values) do
    with {:ok, payload} <- credential_payload(scope, nil, values, options) do
      OperatorAdministration.create_credential(
        authority,
        scope,
        "telnyx",
        "telnyx",
        "api_key",
        payload,
        options
      )
    end
  end

  defp write_credentials(authority, scope, credential, values, options) when is_map(values) do
    with {:ok, payload} <- credential_payload(scope, credential, values, options) do
      OperatorAdministration.update_credential(
        authority,
        scope,
        credential.id,
        "telnyx",
        "api_key",
        payload,
        options
      )
    end
  end

  defp write_credentials(_authority, _scope, _credential, _values, _options),
    do: {:error, :invalid_provider_auth}

  defp credential_payload(scope, credential, values, options) do
    with {:ok, payload} <- merge_saved(scope, credential, values, options),
         true <- Vxpipe.Providers.Telnyx.Credential.public_key?(Map.get(payload, "public_key")),
         :ok <- ProviderAuth.validate("telnyx", "api_key", payload) do
      {:ok, payload}
    else
      false -> {:error, :invalid_provider_auth}
      error -> error
    end
  end

  defp merge_saved(_scope, nil, values, _options), do: {:ok, values}

  defp merge_saved(_scope, _credential, %{"api_key" => _, "public_key" => _} = values, _options),
    do: {:ok, values}

  defp merge_saved(scope, credential, values, options) do
    with {:ok, saved} <- ProviderCredentials.resolve(scope, "telnyx", "telnyx", options),
         true <- saved.credential.id == credential.id do
      {:ok, Map.merge(saved.payload, values)}
    else
      false -> {:error, :provider_credential_unavailable}
      error -> error
    end
  end

  defp save_application(_authority, :platform, %{"application_id" => id}, options),
    do: TelephonyServices.configure_platform_application(id, options)

  defp save_application(authority, tenant, %{"application_id" => id} = attributes, options) do
    with {:ok, service_id} <- selected_service(authority, tenant, attributes, options) do
      case service_id do
        nil ->
          OperatorTelephonyApplications.create(
            authority,
            tenant,
            %{"name" => "telnyx", "provider_connection_id" => id},
            options
          )

        service_id ->
          OperatorTelephonyApplications.update(
            authority,
            tenant,
            service_id,
            %{"provider_connection_id" => id},
            options
          )
      end
      |> saved()
    end
  end

  defp save_application(_authority, _scope, _attributes, _options), do: :ok

  defp selected_service(_authority, _tenant, %{"service_id" => id}, _options)
       when is_binary(id), do: {:ok, id}

  defp selected_service(authority, tenant, _attributes, options) do
    with {:ok, applications} <- applications(authority, tenant, options) do
      case applications do
        [] -> {:ok, nil}
        [application] -> {:ok, application.id}
        _multiple -> {:error, :telephony_service_required}
      end
    end
  end

  defp saved({:ok, _result}), do: :ok
  defp saved(result), do: result
end
