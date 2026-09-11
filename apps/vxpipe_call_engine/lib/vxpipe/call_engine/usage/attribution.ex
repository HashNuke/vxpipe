defmodule Vxpipe.CallEngine.Usage.Attribution do
  @moduledoc """
  Optional call-runtime dimensions supported by evidence for one usage observation.

  An absent dimension remains absent. In particular, participant attribution never implies turn
  or service-interval attribution.
  """

  @fields [
    :room_id,
    :incarnation_id,
    :participant_id,
    :activation_id,
    :service_interval_id,
    :leg_id,
    :turn_id,
    :utterance_id,
    :tool_call_id
  ]

  defstruct @fields

  @type t :: %__MODULE__{
          room_id: String.t() | nil,
          incarnation_id: String.t() | nil,
          participant_id: String.t() | nil,
          activation_id: String.t() | nil,
          service_interval_id: String.t() | nil,
          leg_id: String.t() | nil,
          turn_id: String.t() | nil,
          utterance_id: String.t() | nil,
          tool_call_id: String.t() | nil
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_attribution}
  def new(options) when is_list(options) do
    with {:ok, options} <- Keyword.validate(options, Enum.map(@fields, &{&1, nil})),
         true <- Enum.all?(options, fn {_field, value} -> valid_identifier?(value) end) do
      {:ok, struct!(__MODULE__, options)}
    else
      _invalid -> {:error, :invalid_attribution}
    end
  end

  def new(_options), do: {:error, :invalid_attribution}

  defp valid_identifier?(nil), do: true

  defp valid_identifier?(value) do
    is_binary(value) and String.trim(value) != "" and byte_size(value) <= 128
  end
end
