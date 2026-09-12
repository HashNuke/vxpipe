defmodule Vxpipe.Calls.UsageReport do
  @moduledoc "Effective usage amounts and non-overlapping dimensioned totals for one call."

  alias Vxpipe.CallEngine.Usage.EffectiveAmount
  alias Vxpipe.Calls.{UsageAggregation, UsageTotal}

  @enforce_keys [:amounts, :totals]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          amounts: [EffectiveAmount.t()],
          totals: [UsageTotal.t()]
        }

  @spec new([EffectiveAmount.t()]) :: {:ok, t()} | {:error, :invalid_usage_amounts}
  def new(amounts) when is_list(amounts) do
    if Enum.all?(amounts, &match?(%EffectiveAmount{}, &1)) do
      {:ok, %__MODULE__{amounts: amounts, totals: UsageAggregation.derive(amounts)}}
    else
      {:error, :invalid_usage_amounts}
    end
  end

  def new(_amounts), do: {:error, :invalid_usage_amounts}
end
