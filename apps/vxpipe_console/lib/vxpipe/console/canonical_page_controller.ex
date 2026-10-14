defmodule Vxpipe.Console.CanonicalPageController do
  @moduledoc "Canonical page entry and safe redirects for legacy Console bookmarks."
  use Phoenix.Controller, formats: [:html]

  alias Vxpipe.Console.AdminPageController

  def index(conn, %{"tenant_key" => key} = params) do
    case Vxpipe.Calls.fetch_visible_tenant(conn.assigns.user_principal, key) do
      {:ok, _tenant} -> AdminPageController.index(conn, params)
      {:error, :tenant_not_found} -> send_resp(conn, 404, "Not found")
      {:error, _} -> send_resp(conn, 503, "Workspace unavailable")
    end
  end

  def index(conn, params) do
    case conn.path_info do
      ["my-tenants"] -> redirect(conn, to: "/tenants" <> query_suffix(conn))
      _ -> AdminPageController.index(conn, params)
    end
  end

  def legacy(conn, params) do
    case destination(conn.path_info) do
      nil -> AdminPageController.index(conn, params)
      path -> redirect(conn, to: path <> query_suffix(conn))
    end
  end

  defp destination(["admin"]), do: "/"
  defp destination(["admin", "onboarding"]), do: "/getting-started"
  defp destination(["admin", "account"]), do: "/account"
  defp destination(["admin", "platform", "services"]), do: "/platform/services"

  defp destination(["admin", kind | rest]) when kind in ["users", "roles"],
    do: "/" <> Enum.map_join([kind | rest], "/", &segment/1)

  defp destination(["admin", "tenants", key]), do: "/t/#{segment(key)}/dashboard"
  defp destination(["admin", "tenants", key, "setup-services"]), do: "/t/#{segment(key)}/services"

  defp destination(["admin", "tenants", key, leaf])
       when leaf in ["calls", "call-specs", "services"],
       do: "/t/#{segment(key)}/#{leaf}"

  defp destination(_), do: nil

  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp query_suffix(conn) do
    conn = fetch_query_params(conn)

    query =
      conn.query_params
      |> Map.take(["page", "q", "role", "call_spec_id"])
      |> Enum.filter(fn {_key, value} -> is_binary(value) end)
      |> Enum.sort()
      |> URI.encode_query()

    if query == "", do: "", else: "?" <> query
  end
end
