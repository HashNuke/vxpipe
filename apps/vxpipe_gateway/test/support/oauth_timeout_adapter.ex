defmodule Vxpipe.Gateway.Test.OAuthTimeoutAdapter do
  @moduledoc false
  def read_req_body(_state, _options), do: {:error, :timeout}
  defdelegate send_resp(state, status, headers, body), to: Plug.Adapters.Test.Conn
end
