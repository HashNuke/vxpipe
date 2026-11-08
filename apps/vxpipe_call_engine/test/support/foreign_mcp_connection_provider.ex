defmodule Vxpipe.CallEngine.ForeignMCPConnectionProvider do
  @moduledoc false

  def open(_key, config, _options), do: {:ok, Keyword.fetch!(config, :foreign_connection)}
end
