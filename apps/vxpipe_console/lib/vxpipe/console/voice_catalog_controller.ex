defmodule Vxpipe.Console.VoiceCatalogController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]
  alias Vxpipe.Calls.ProviderCatalogErrors

  def describe(conn, params), do: request(conn, params, :describe)
  def index(conn, params), do: request(conn, params, :list)
  def show(conn, %{"voice_id" => id} = params), do: request(conn, params, {:get, id})

  defp request(conn, params, operation) do
    scope = %{
      provider: params["provider"],
      capability: params["capability"],
      model: params["model"],
      credential_name: Map.get(params, "credential_name", "default")
    }

    result =
      with {:ok, filters} <- filters(Map.get(params, "filters", "{}")) do
        query = params |> Map.take(["search", "cursor"]) |> Map.put("filters", filters)

        Vxpipe.Calls.voice_catalog(
          conn.assigns.user_principal,
          params["tenant_key"],
          scope,
          operation,
          query
        )
      end

    respond(result, conn, operation)
  end

  defp filters(value) when is_binary(value) and byte_size(value) <= 4096 do
    case JSON.decode(value) do
      {:ok, filters} when is_map(filters) -> {:ok, filters}
      _ -> {:error, :invalid_voice_query}
    end
  end

  defp filters(_), do: {:error, :invalid_voice_query}

  defp respond({:ok, result}, conn, operation) do
    body = if match?({:get, _}, operation), do: %{voice: result}, else: result
    conn |> put_resp_header("cache-control", "no-store") |> json(body)
  end

  defp respond({:error, reason}, conn, _) do
    {status, error} = error(reason)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(%{error: error})
  end

  defp error(reason) when reason in [:invalid_voice_scope, :invalid_voice_query],
    do: {422, %{code: Atom.to_string(reason)}}

  defp error(:voice_catalog_rate_limited), do: {429, %{code: "voice_catalog_rate_limited"}}
  defp error(:invalid_voice_catalog_response), do: {502, %{code: "voice_catalog_unavailable"}}
  defp error(:voice_catalog_unavailable), do: {503, %{code: "voice_catalog_unavailable"}}

  defp error(reason)
       when reason in [:voice_catalog_credentials_rejected, :provider_credential_unavailable],
       do: {422, %{code: "provider_credential_unavailable"}}

  defp error(reason), do: ProviderCatalogErrors.response(reason)
end
