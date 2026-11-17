defmodule Vxpipe.CallEngine.Tool.Idle.Request do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.Context

  @derive {Inspect, only: [:duration_seconds]}
  @enforce_keys [:context, :duration_seconds]
  defstruct @enforce_keys

  @type t :: %__MODULE__{context: Context.t(), duration_seconds: pos_integer()}

  @minimum_seconds 1
  @maximum_seconds 300
  @arming_timeout_ms 30_000
  @settlement_grace_ms 5_000

  def minimum_seconds, do: @minimum_seconds
  def maximum_seconds, do: @maximum_seconds
  def arming_timeout_ms, do: @arming_timeout_ms
  def settlement_grace_ms, do: @settlement_grace_ms

  @spec new(term(), Context.t()) :: {:ok, t()} | {:error, :invalid_arguments}
  def new(%{"duration_seconds" => seconds} = arguments, %Context{tool_call_id: id} = context)
      when map_size(arguments) == 1 and is_integer(seconds) and
             seconds >= @minimum_seconds and seconds <= @maximum_seconds and
             is_binary(id) and id != "" and byte_size(id) <= 256 do
    {:ok, %__MODULE__{context: context, duration_seconds: seconds}}
  end

  def new(_arguments, %Context{}), do: {:error, :invalid_arguments}

  @spec execution_timeout_ms(t()) :: pos_integer()
  def execution_timeout_ms(%__MODULE__{} = request),
    do: request.duration_seconds * 1_000 + @arming_timeout_ms + @settlement_grace_ms
end
