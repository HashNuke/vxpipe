defmodule Vxpipe.Console.AssignInstallationCallAccess do
  @moduledoc "Scopes an authenticated installation operator to one tenant's call resources."

  @behaviour Plug

  import Plug.Conn

  alias Vxpipe.Calls.InstallationOperator

  @impl true
  def init(options), do: options

  @impl true
  def call(
        %Plug.Conn{
          assigns: %{installation_operator: _grant},
          path_params: %{"tenant_key" => tenant_key}
        } = conn,
        _options
      ) do
    case Vxpipe.Calls.operator_call_access(InstallationOperator.authority(), tenant_key) do
      {:ok, access} -> assign(conn, :call_read_access, access)
      {:error, _reason} -> conn |> send_resp(404, "not found") |> halt()
    end
  end

  def call(%Plug.Conn{} = conn, _options), do: conn |> send_resp(404, "not found") |> halt()
end
