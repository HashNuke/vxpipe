defmodule Vxpipe.CallEngine.ForeignMCPConnectionProvider do
  @moduledoc false

  def open(_key, config), do: {:ok, Keyword.fetch!(config, :foreign_connection)}
  def open(key, config, _options), do: open(key, config)
end
