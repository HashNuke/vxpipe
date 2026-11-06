defmodule Vxpipe.MCP.CheckLogCapture do
  @moduledoc false
  def log(event, %{config: %{owner: owner}}), do: send(owner, {:check_log, event})
end
