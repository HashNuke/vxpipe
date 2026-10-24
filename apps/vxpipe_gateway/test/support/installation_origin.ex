defmodule Vxpipe.Gateway.TestInstallationOrigin do
  def public_url, do: Process.get(__MODULE__, {:ok, nil})
end
