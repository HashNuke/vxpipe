defmodule Vxpipe.Persistence.CallDetailsTimestamp do
  @moduledoc false

  @spec format(DateTime.t() | nil) :: String.t() | nil
  def format(nil), do: nil
  def format(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
