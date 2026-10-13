defmodule Vxpipe.Identity.Clock do
  @moduledoc false
  @spec utc_now() :: DateTime.t()
  def utc_now, do: DateTime.utc_now()
end
