defmodule Vxpipe.Web do
  @moduledoc """
  Reusable Plug and WebSocket integration for Vxpipe.

  This application does not open a network port. Host applications can mount
  `Vxpipe.Web.Router`, while the standalone `vxpipe_server` application serves
  it with Bandit.
  """
end
