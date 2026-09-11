defmodule Vxpipe.CallEngine.Usage.Measurement do
  @moduledoc """
  One exact measured component reported for a provider-operation attempt.

  Counts and durations are non-negative integers. Monetary quantities are non-negative exact
  decimals paired with an ISO-style uppercase currency code; floats are deliberately rejected.
  """

  @modes [:delta, :cumulative]
  @statuses [:estimate, :final, :correction]
  @provenances [:provider_reported, :locally_measured, :library_estimate, :billing_lookup]
  @scalar_units [:tokens, :characters, :milliseconds, :requests]

  @enforce_keys [:component, :unit, :quantity, :mode, :status, :provenance]
  defstruct @enforce_keys ++ [included_in: nil]

  @type mode :: :delta | :cumulative
  @type status :: :estimate | :final | :correction

  @type provenance ::
          :provider_reported | :locally_measured | :library_estimate | :billing_lookup

  @type unit :: :tokens | :characters | :milliseconds | :requests | {:currency, String.t()}
  @type quantity :: non_neg_integer() | Decimal.t()

  @type t :: %__MODULE__{
          component: String.t(),
          unit: unit(),
          quantity: quantity(),
          mode: mode(),
          status: status(),
          provenance: provenance(),
          included_in: String.t() | nil
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_measurement}
  def new(options) when is_list(options) do
    with {:ok, options} <-
           Keyword.validate(options,
             component: nil,
             unit: nil,
             quantity: nil,
             mode: nil,
             status: nil,
             provenance: nil,
             included_in: nil
           ),
         component when is_binary(component) <- Keyword.get(options, :component),
         true <- valid_component?(component),
         included_in <- Keyword.get(options, :included_in),
         true <- is_nil(included_in) or valid_component?(included_in),
         true <- included_in != component,
         unit <- Keyword.get(options, :unit),
         {:ok, quantity} <- normalize_quantity(unit, Keyword.get(options, :quantity)),
         mode when mode in @modes <- Keyword.get(options, :mode),
         status when status in @statuses <- Keyword.get(options, :status),
         provenance when provenance in @provenances <- Keyword.get(options, :provenance) do
      {:ok,
       %__MODULE__{
         component: component,
         unit: unit,
         quantity: quantity,
         mode: mode,
         status: status,
         provenance: provenance,
         included_in: included_in
       }}
    else
      _invalid -> {:error, :invalid_measurement}
    end
  end

  def new(_options), do: {:error, :invalid_measurement}

  defp valid_component?(component) do
    byte_size(component) <= 64 and Regex.match?(~r/^[a-z][a-z0-9_]*$/, component)
  end

  defp normalize_quantity(unit, quantity) when unit in @scalar_units do
    if is_integer(quantity) and quantity >= 0,
      do: {:ok, quantity},
      else: {:error, :invalid_quantity}
  end

  defp normalize_quantity({:currency, currency}, quantity)
       when is_binary(currency) and is_binary(quantity) do
    with true <- Regex.match?(~r/^[A-Z]{3}$/, currency),
         true <- Regex.match?(~r/^\d+(?:\.\d+)?$/, quantity),
         {decimal, ""} <- Decimal.parse(quantity) do
      {:ok, decimal}
    else
      _invalid -> {:error, :invalid_quantity}
    end
  end

  defp normalize_quantity({:currency, currency}, %Decimal{} = quantity)
       when is_binary(currency) do
    normalize_quantity({:currency, currency}, Decimal.to_string(quantity, :normal))
  end

  defp normalize_quantity(_unit, _quantity), do: {:error, :invalid_quantity}
end
