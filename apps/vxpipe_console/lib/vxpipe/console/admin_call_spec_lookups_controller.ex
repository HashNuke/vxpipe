defmodule Vxpipe.Console.AdminCallSpecLookupsController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]
  alias Vxpipe.Calls.InstallationOperator

  def index(conn, %{"tenant_key" => tenant}) do
    case Vxpipe.Calls.list_call_spec_editor_lookups(InstallationOperator.authority(), tenant) do
      {:ok, lookups} ->
        json(conn, lookups)

      {:error, :tenant_not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "tenant_not_found"}})

      {:error, _reason} ->
        unavailable(conn)
    end
  rescue
    _error -> unavailable(conn)
  catch
    :exit, _reason -> unavailable(conn)
  end

  defp unavailable(conn),
    do: conn |> put_status(503) |> json(%{error: %{code: "call_spec_lookups_unavailable"}})
end
