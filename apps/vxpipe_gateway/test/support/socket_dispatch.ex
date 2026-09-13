defmodule Vxpipe.Gateway.TestSocketDispatch do
  @moduledoc false

  def await(socket) do
    if :gen_server.reqids_size(socket.dispatch.requests) == 0 do
      {:ok, socket}
    else
      case :gen_server.receive_response(socket.dispatch.requests, 5_000, true) do
        {{:reply, :ok}, {_, timer}, requests} ->
          Process.cancel_timer(timer)
          await(%{socket | dispatch: %{socket.dispatch | requests: requests}})

        _ ->
          {:error, :media_dispatch_failed}
      end
    end
  end
end
