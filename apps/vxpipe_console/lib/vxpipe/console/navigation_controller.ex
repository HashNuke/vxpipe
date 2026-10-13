defmodule Vxpipe.Console.NavigationController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  def show(conn, params) do
    case Vxpipe.Console.NavigationProjection.build(
           conn.assigns.user_principal,
           Map.get(params, "tenant")
         ) do
      {:ok, navigation} ->
        json(conn, navigation)

      {:error, :tenant_not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "tenant_not_found"}})

      {:error, _} ->
        conn |> put_status(503) |> json(%{error: %{code: "navigation_unavailable"}})
    end
  end
end
