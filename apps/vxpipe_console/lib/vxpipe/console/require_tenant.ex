defmodule Vxpipe.Console.RequireTenant do
  @moduledoc "Ensures a tenant-scoped Console URL matches the signed operator session."

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(options), do: options

  @impl true
  def call(
        %Plug.Conn{
          assigns: %{operator_principal: %{tenant_key: tenant_key}},
          path_params: %{"tenant_key" => tenant_key}
        } = conn,
        _options
      ),
      do: conn

  def call(%Plug.Conn{} = conn, _options) do
    conn
    |> send_resp(404, "not found")
    |> halt()
  end
end
