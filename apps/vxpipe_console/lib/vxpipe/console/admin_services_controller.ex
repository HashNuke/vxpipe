defmodule Vxpipe.Console.AdminServicesController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Calls.InstallationOperator
  alias Vxpipe.Gateway.Telephony.Telnyx.PublicEndpoint

  def platform_index(conn, _params), do: bindings(conn, :platform)
  def tenant_bindings(conn, %{"tenant_key" => key}), do: bindings(conn, key)

  def delete(conn, %{"tenant_key" => key, "credential_id" => id}),
    do: delete_credential(conn, key, id)

  def delete_platform(conn, %{"credential_id" => id}), do: delete_credential(conn, :platform, id)

  defp delete_credential(conn, owner, id) do
    case Vxpipe.Calls.delete_operator_credential(InstallationOperator.authority(), owner, id) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, reason} when reason in [:tenant_not_found, :provider_credential_not_found] ->
        conn |> put_status(404) |> json(%{error: %{code: Atom.to_string(reason)}})

      {:error, :provider_credential_in_use} ->
        conn |> put_status(409) |> json(%{error: %{code: "provider_credential_in_use"}})

      {:error, reason} when reason in [:invalid_tenant_key, :invalid_provider_credential_id] ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_credential"}})

      {:error, _reason} ->
        conn |> put_status(503) |> json(%{error: %{code: "credential_store_unavailable"}})
    end
  end

  defp bindings(conn, scope) do
    case Vxpipe.Calls.list_operator_service_bindings(InstallationOperator.authority(), scope) do
      {:ok, directory} ->
        origin = Application.fetch_env!(:vxpipe_console, :service_public_origin)

        urls = %{
          platform: PublicEndpoint.scoped_event_url(origin, :platform),
          tenant:
            if(is_binary(scope), do: PublicEndpoint.scoped_event_url(origin, {:tenant, scope}))
        }

        json(conn, Map.put(directory, :webhook_urls, urls))

      {:error, :tenant_not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "tenant_not_found"}})

      {:error, _reason} ->
        conn |> put_status(503) |> json(%{error: %{code: "service_directory_unavailable"}})
    end
  end

  def index(conn, %{"tenant_key" => tenant_key}) do
    case Vxpipe.Calls.list_operator_services(InstallationOperator.authority(), tenant_key) do
      {:ok, directory} ->
        json(conn, %{
          tenant: %{key: directory.tenant.key, name: directory.tenant.name},
          credentials: Enum.map(directory.credentials, &credential_json/1),
          telephony_services: Enum.map(directory.telephony_services, &telephony_json/1),
          truncated: directory.truncated
        })

      {:error, :tenant_not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "tenant_not_found"}})

      {:error, _reason} ->
        conn
        |> put_status(503)
        |> json(%{error: %{code: "service_directory_unavailable"}})
    end
  end

  def create(conn, %{"tenant_key" => tenant_key} = params) do
    create_credential(
      conn,
      tenant_key,
      params,
      Map.get(params, "name", Map.get(params, "provider"))
    )
  end

  def create_platform(conn, params) do
    name = Map.get(params, "name", Map.get(params, "provider"))
    create_credential(conn, :platform, params, name)
  end

  defp create_credential(conn, owner, params, name) do
    with {:ok, provider, auth_kind, payload} <- credential_input(params),
         {:ok, credential} <-
           Vxpipe.Calls.create_validated_operator_credential(
             InstallationOperator.authority(),
             owner,
             provider,
             name,
             auth_kind,
             payload
           ) do
      conn |> put_status(201) |> json(%{credential: credential_json(credential)})
    else
      {:error, :tenant_not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "tenant_not_found"}})

      {:error, :provider_credential_conflict} ->
        conn |> put_status(409) |> json(%{error: %{code: "credential_already_exists"}})

      {:error, reason}
      when reason in [:invalid_provider_auth, :invalid_credential_name, :invalid_tenant_key] ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_credential"}})

      {:error, :provider_credential_rejected} ->
        conn |> put_status(422) |> json(%{error: %{code: "credential_rejected"}})

      {:error, :provider_validation_unavailable} ->
        conn |> put_status(503) |> json(%{error: %{code: "credential_validation_unavailable"}})

      {:error, _reason} ->
        conn |> put_status(503) |> json(%{error: %{code: "credential_store_unavailable"}})
    end
  end

  def update(
        conn,
        %{"tenant_key" => tenant_key, "credential_id" => credential_id} = params
      ) do
    update_credential(conn, tenant_key, credential_id, params)
  end

  def update_platform(conn, %{"credential_id" => id} = params) do
    update_credential(conn, :platform, id, params)
  end

  defp update_credential(conn, owner, credential_id, params) do
    with {:ok, provider, auth_kind, payload} <- credential_input(params),
         {:ok, credential} <-
           Vxpipe.Calls.update_validated_operator_credential(
             InstallationOperator.authority(),
             owner,
             credential_id,
             provider,
             auth_kind,
             payload
           ) do
      json(conn, %{credential: credential_json(credential)})
    else
      {:error, reason}
      when reason in [:tenant_not_found, :provider_credential_not_found] ->
        conn |> put_status(404) |> json(%{error: %{code: "credential_not_found"}})

      {:error, reason}
      when reason in [
             :invalid_provider_auth,
             :invalid_credential_name,
             :invalid_tenant_key,
             :invalid_provider_credential_id
           ] ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_credential"}})

      {:error, :provider_credential_rejected} ->
        conn |> put_status(422) |> json(%{error: %{code: "credential_rejected"}})

      {:error, :provider_validation_unavailable} ->
        conn |> put_status(503) |> json(%{error: %{code: "credential_validation_unavailable"}})

      {:error, _reason} ->
        conn |> put_status(503) |> json(%{error: %{code: "credential_store_unavailable"}})
    end
  end

  defp credential_input(%{
         "provider" => "telnyx",
         "values" => %{"api_key" => _api_key, "public_key" => _public_key} = values
       })
       when map_size(values) == 2,
       do: {:ok, "telnyx", "api_key", values}

  defp credential_input(%{
         "provider" => provider,
         "values" => %{"api_key" => api_key} = values
       })
       when provider in ["google", "deepgram", "zenmux", "telnyx", "rime"] and
              map_size(values) == 1 do
    {:ok, provider, "api_key", %{"api_key" => api_key}}
  end

  defp credential_input(%{
         "provider" => "twilio",
         "values" => %{"account_sid" => account_sid, "auth_token" => auth_token} = values
       })
       when map_size(values) == 2 do
    {:ok, "twilio", "account_sid_auth_token",
     %{"account_sid" => account_sid, "auth_token" => auth_token}}
  end

  defp credential_input(_params), do: {:error, :invalid_provider_auth}

  defp credential_json(credential) do
    %{
      id: credential.id,
      provider: credential.provider,
      name: credential.name,
      auth_kind: credential.auth_kind,
      status: Atom.to_string(credential.status),
      credential_preview: credential_preview(credential),
      last_validated_at: datetime_json(credential.last_validated_at),
      created_at: datetime_json(credential.inserted_at),
      updated_at: datetime_json(credential.updated_at)
    }
  end

  defp credential_preview(%{auth_kind: "api_key", secret_hints: hints}) do
    [preview("API key", Map.get(hints, "api_key"))]
  end

  defp credential_preview(%{auth_kind: "account_sid_auth_token", secret_hints: hints}) do
    [preview("Account SID", Map.get(hints, "account_sid")), masked("Auth token")]
  end

  defp preview(label, last_four) when is_binary(last_four) and byte_size(last_four) == 4,
    do: %{label: label, format: "last_four", last_four: last_four}

  defp preview(label, _missing), do: masked(label)
  defp masked(label), do: %{label: label, format: "masked"}

  defp telephony_json(service) do
    %{
      id: service.id,
      name: service.name,
      provider: service.provider,
      provider_connection_id: service.provider_connection_id,
      credential_id: service.credential_id,
      outbound_number: service.outbound_number
    }
  end

  defp datetime_json(nil), do: nil
  defp datetime_json(datetime), do: DateTime.to_iso8601(datetime)
end
