defmodule Vxpipe.Console.AdminServicesController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Calls.InstallationOperator

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
    with {:ok, provider, auth_kind, payload} <- credential_input(params),
         {:ok, credential} <-
           Vxpipe.Calls.create_operator_credential(
             InstallationOperator.authority(),
             tenant_key,
             provider,
             provider,
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

      {:error, _reason} ->
        conn |> put_status(503) |> json(%{error: %{code: "credential_store_unavailable"}})
    end
  end

  def update(
        conn,
        %{"tenant_key" => tenant_key, "credential_id" => credential_id} = params
      ) do
    with {:ok, provider, auth_kind, payload} <- credential_input(params),
         {:ok, credential} <-
           Vxpipe.Calls.update_operator_credential(
             InstallationOperator.authority(),
             tenant_key,
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

      {:error, _reason} ->
        conn |> put_status(503) |> json(%{error: %{code: "credential_store_unavailable"}})
    end
  end

  defp credential_input(%{
         "provider" => provider,
         "values" => %{"api_key" => api_key} = values
       })
       when provider in ["google", "deepgram", "zenmux", "telnyx"] and
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
