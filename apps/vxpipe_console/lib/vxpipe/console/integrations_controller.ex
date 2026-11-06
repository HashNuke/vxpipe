defmodule Vxpipe.Console.IntegrationsController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.IntegrationsDirectory.Inventory

  def categories(conn, %{"tenant_key" => tenant}) do
    case Vxpipe.Console.IntegrationsDirectory.Categories.list(conn.assigns.user_principal, tenant) do
      {:ok, categories} -> json(conn, categories)
      {:error, reason} -> conn |> put_status(status(reason)) |> json(%{error: %{code: reason}})
    end
  end

  def platform(conn, params), do: list(conn, :platform, params)

  def tenant(conn, %{"tenant_key" => tenant} = params),
    do: list(conn, tenant, Map.delete(params, "tenant_key"))

  defp list(conn, scope, params) do
    case Inventory.list(conn.assigns.user_principal, scope, normalize_limit(params)) do
      {:ok, inventory} -> json(conn, inventory)
      {:error, reason} -> conn |> put_status(status(reason)) |> json(%{error: %{code: reason}})
    end
  end

  defp normalize_limit(%{"limit" => limit} = params) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} -> Map.put(params, "limit", value)
      _invalid -> params
    end
  end

  defp normalize_limit(params), do: params

  defp status(:forbidden), do: 403
  defp status(reason) when reason in [:tenant_not_found, :category_unavailable], do: 404
  defp status(:cursor_expired), do: 410
  defp status(reason) when reason in [:invalid_cursor, :cursor_mismatch], do: 400
  defp status(reason) when reason in [:invalid_query, :invalid_tenant_key], do: 422
  defp status(_reason), do: 503
end
