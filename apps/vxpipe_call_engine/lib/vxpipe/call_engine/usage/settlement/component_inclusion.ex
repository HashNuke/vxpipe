defmodule Vxpipe.CallEngine.Usage.Settlement.ComponentInclusion do
  @moduledoc "Validates aggregate/subcategory relations and identifies top-level amounts."

  alias Vxpipe.CallEngine.Usage.EffectiveAmount

  @spec validate([EffectiveAmount.t()]) :: :ok | {:error, :invalid_inclusion}
  def validate(amounts) do
    Enum.reduce_while(amounts, :ok, fn
      %EffectiveAmount{included_in: nil}, :ok ->
        {:cont, :ok}

      %EffectiveAmount{} = amount, :ok ->
        if Enum.any?(amounts, &target?(&1, amount)) do
          {:cont, :ok}
        else
          {:halt, {:error, :invalid_inclusion}}
        end
    end)
  end

  @spec root?(EffectiveAmount.t()) :: boolean()
  def root?(%EffectiveAmount{included_in: nil}), do: true
  def root?(%EffectiveAmount{}), do: false

  defp target?(candidate, amount) do
    candidate.component == amount.included_in and candidate.unit == amount.unit and
      candidate.attempt_id == amount.attempt_id and candidate.capability == amount.capability and
      candidate.provider == amount.provider and candidate.attribution == amount.attribution and
      candidate.provenance == amount.provenance
  end
end
