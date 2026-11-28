defmodule Vxpipe.CallEngine.Usage.Decisions do
  @moduledoc "Token measurements reported for a physical Decisions request."

  @doc "Returns only reported token components, with a parent total when available."
  def token_components(usage) when is_map(usage) do
    total = Map.get(usage, :total_tokens)

    for key <- [:input_tokens, :output_tokens, :total_tokens],
        quantity = Map.get(usage, key),
        is_integer(quantity) and quantity >= 0 do
      parent = if key != :total_tokens and is_integer(total) and total >= 0, do: "total_tokens"
      {Atom.to_string(key), quantity, parent}
    end
  end

  def token_components(_unknown), do: []
end
