defmodule Vxpipe.CallEngine.RemoteMCP.ConfigurationSource do
  @moduledoc """
  Supplies one complete set of validated remote MCP integration configurations.

  Implementations may read OTP application settings or a host-owned tenant/vault boundary.
  """

  alias Vxpipe.CallEngine.RemoteMCP.ConfiguredIntegration

  @type error :: term()

  @callback fetch(keyword()) :: {:ok, [ConfiguredIntegration.t()]} | {:error, error()}
end
