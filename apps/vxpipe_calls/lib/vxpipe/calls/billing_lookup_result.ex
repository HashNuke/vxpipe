defmodule Vxpipe.Calls.BillingLookupResult do
  @moduledoc "One versioned provider billing amount returned by a configured lookup adapter."

  alias Vxpipe.CallEngine.Usage.Measurement

  @derive {Inspect, only: [:source_sequence, :measurement, :observed_at]}
  @enforce_keys [:delivery_id, :measurement, :observed_at]
  defstruct @enforce_keys ++ [source_sequence: nil]

  @type t :: %__MODULE__{
          delivery_id: String.t(),
          source_sequence: non_neg_integer() | nil,
          measurement: Measurement.t(),
          observed_at: DateTime.t()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_billing_lookup_result}
  def new(options) when is_list(options) do
    with {:ok, options} <-
           Keyword.validate(options,
             delivery_id: nil,
             source_sequence: nil,
             component: "cost",
             amount: nil,
             currency: nil,
             status: nil,
             observed_at: nil
           ),
         delivery_id when is_binary(delivery_id) <- Keyword.get(options, :delivery_id),
         true <- delivery_id != "" and byte_size(delivery_id) <= 128,
         source_sequence <- Keyword.get(options, :source_sequence),
         true <- valid_sequence?(source_sequence),
         %DateTime{} = observed_at <- Keyword.get(options, :observed_at),
         {:ok, measurement} <-
           Measurement.new(
             component: Keyword.get(options, :component),
             unit: {:currency, Keyword.get(options, :currency)},
             quantity: Keyword.get(options, :amount),
             mode: :cumulative,
             status: Keyword.get(options, :status),
             provenance: :billing_lookup
           ) do
      {:ok,
       %__MODULE__{
         delivery_id: delivery_id,
         source_sequence: source_sequence,
         measurement: measurement,
         observed_at: observed_at
       }}
    else
      _invalid -> {:error, :invalid_billing_lookup_result}
    end
  end

  def new(_options), do: {:error, :invalid_billing_lookup_result}

  defp valid_sequence?(nil), do: true
  defp valid_sequence?(value), do: is_integer(value) and value >= 0
end
