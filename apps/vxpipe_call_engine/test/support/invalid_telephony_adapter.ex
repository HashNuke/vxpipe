defmodule Vxpipe.CallEngine.InvalidTelephonyAdapter do
  @moduledoc false

  def dial(_config, _request), do: :submitted
end
