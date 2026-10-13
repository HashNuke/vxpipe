defmodule Vxpipe.Console.AssignUserCallAccess do
  @moduledoc "Pins an authenticated user's call-read authority to one tenant."

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(options), do: options

  @impl true
  def call(
        %Plug.Conn{
          assigns: %{user_principal: principal},
          path_params: %{"tenant_key" => tenant_key}
        } = conn,
        _options
      ) do
    case Vxpipe.Calls.user_call_access(principal, tenant_key) do
      {:ok, access} -> assign(conn, :call_read_access, access)
      {:error, _reason} -> conn |> send_resp(404, "not found") |> halt()
    end
  end

  def call(%Plug.Conn{} = conn, _options), do: conn |> send_resp(404, "not found") |> halt()
end
