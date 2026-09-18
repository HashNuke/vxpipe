defmodule Vxpipe.CallEngine.CallSpec.TransferPolicy do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpecValidation

  @default_attempt_timeout_ms 30_000
  @minimum_attempt_timeout_ms 1_000
  @maximum_attempt_timeout_ms 120_000
  @path ["transfer_policy"]
  @code :invalid_call_spec
  @message "The call spec is invalid."

  @enforce_keys [:attempt_timeout_ms]
  defstruct @enforce_keys

  @type t :: %__MODULE__{attempt_timeout_ms: pos_integer()}

  @spec new(nil | map()) :: {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def new(value) when value in [nil, %{}] do
    {:ok, %__MODULE__{attempt_timeout_ms: @default_attempt_timeout_ms}}
  end

  def new(value) do
    with {:ok, input} <-
           CallSpecValidation.normalize_map(
             value,
             [:attempt_timeout_ms],
             @code,
             @message,
             @path
           ),
         {:ok, timeout} <- attempt_timeout(input) do
      {:ok, %__MODULE__{attempt_timeout_ms: timeout}}
    end
  end

  defp attempt_timeout(input) do
    case Map.fetch(input, :attempt_timeout_ms) do
      :error ->
        {:ok, @default_attempt_timeout_ms}

      {:ok, value}
      when is_integer(value) and value >= @minimum_attempt_timeout_ms and
             value <= @maximum_attempt_timeout_ms ->
        {:ok, value}

      {:ok, _invalid} ->
        CallSpecValidation.invalid(
          @code,
          @message,
          @path ++ ["attempt_timeout_ms"],
          "must be between #{@minimum_attempt_timeout_ms} and #{@maximum_attempt_timeout_ms}"
        )
    end
  end
end
