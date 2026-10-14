defmodule Vxpipe.Persistence.CallSpecId do
  @moduledoc false

  # Invalid external references match no row, without passing malformed values
  # to Ecto's bigint cast. IDs stay strings on the wire to avoid JS precision loss.
  def database_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 -> id
      _invalid -> 0
    end
  end

  def database_id(_value), do: 0
end
