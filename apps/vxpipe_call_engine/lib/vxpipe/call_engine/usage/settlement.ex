defmodule Vxpipe.CallEngine.Usage.Settlement do
  @moduledoc """
  Derives effective usage without losing the immutable source observations.

  Included component amounts remain inspectable but are omitted from overall totals. Totals with
  multiple provenances must be selected explicitly instead of silently combining reported and
  estimated values.
  """

  alias Vxpipe.CallEngine.Usage.{EffectiveAmount, Measurement, Observation}

  alias Vxpipe.CallEngine.Usage.Settlement.{
    AmountDerivation,
    ComponentInclusion
  }

  @enforce_keys [:tenant_id, :call_id, :amounts]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          call_id: String.t(),
          amounts: [EffectiveAmount.t()]
        }

  @type error ::
          :empty_observations
          | :mixed_calls
          | :conflicting_delivery
          | :mixed_measurement_modes
          | :ambiguous_cumulative_order
          | :invalid_inclusion

  @spec derive([Observation.t()]) :: {:ok, t()} | {:error, error()}
  def derive([%Observation{} = first | _rest] = observations) do
    with :ok <- one_call?(observations, first),
         {:ok, amounts} <- AmountDerivation.derive(observations),
         :ok <- ComponentInclusion.validate(amounts) do
      {:ok,
       %__MODULE__{
         tenant_id: first.tenant_id,
         call_id: first.call_id,
         amounts: Enum.sort_by(amounts, &amount_sort_key/1)
       }}
    end
  end

  def derive([]), do: {:error, :empty_observations}
  def derive(_observations), do: {:error, :mixed_calls}

  @spec total(t(), Measurement.unit(), keyword()) ::
          {:ok, Measurement.quantity()}
          | {:error, :unknown_unit | :ambiguous_provenance | :invalid_total_options}
  def total(settlement, unit, options \\ [])

  def total(%__MODULE__{amounts: amounts}, unit, options) when is_list(options) do
    with {:ok, options} <- Keyword.validate(options, provenance: nil),
         selected <- select_total_amounts(amounts, unit, Keyword.get(options, :provenance)),
         :ok <- one_provenance?(selected) do
      sum_total(selected)
    else
      {:error, keys} when is_list(keys) -> {:error, :invalid_total_options}
      {:error, reason} -> {:error, reason}
    end
  end

  def total(%__MODULE__{}, _unit, _options), do: {:error, :invalid_total_options}

  defp one_call?(observations, first) do
    if Enum.all?(observations, fn
         %Observation{tenant_id: tenant_id, call_id: call_id} ->
           tenant_id == first.tenant_id and call_id == first.call_id

         _invalid ->
           false
       end),
       do: :ok,
       else: {:error, :mixed_calls}
  end

  defp select_total_amounts(amounts, unit, nil) do
    Enum.filter(amounts, &(&1.unit == unit and ComponentInclusion.root?(&1)))
  end

  defp select_total_amounts(amounts, unit, provenance) do
    Enum.filter(
      amounts,
      &(&1.unit == unit and ComponentInclusion.root?(&1) and &1.provenance == provenance)
    )
  end

  defp one_provenance?(amounts) do
    case amounts |> Enum.map(& &1.provenance) |> Enum.uniq() do
      [_one] -> :ok
      [] -> :ok
      _multiple -> {:error, :ambiguous_provenance}
    end
  end

  defp sum_total([]), do: {:error, :unknown_unit}

  defp sum_total([%EffectiveAmount{quantity: first} | rest]) do
    {:ok, Enum.reduce(rest, first, fn amount, total -> add(amount.quantity, total) end)}
  end

  defp amount_sort_key(amount) do
    {
      amount.component,
      amount.unit,
      amount.attempt_id,
      amount.provider,
      amount.attribution
    }
  end

  defp add(%Decimal{} = left, %Decimal{} = right), do: Decimal.add(left, right)
  defp add(left, right) when is_integer(left) and is_integer(right), do: left + right
end
