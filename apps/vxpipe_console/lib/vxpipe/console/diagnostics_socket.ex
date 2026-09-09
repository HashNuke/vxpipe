defmodule Vxpipe.Console.DiagnosticsSocket do
  @moduledoc false

  use Phoenix.LiveView.Socket

  alias Vxpipe.Console.DiagnosticsEnabled

  @impl Phoenix.Socket
  def connect(_params, socket, _connect_info) do
    if DiagnosticsEnabled.enabled?(), do: {:ok, socket}, else: :error
  end

  @impl Phoenix.Socket
  def id(socket), do: Phoenix.LiveView.Socket.id(socket)
end
