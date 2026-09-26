defmodule Vxpipe.Providers.OpenAI.GPTLiveUsage do
  @moduledoc "Cumulative voice duration and distinct backend token reports."

  @derive {Inspect, only: [:backend_model, :voice_ms]}
  defstruct [:backend_model, voice_ms: 0, seen_responses: MapSet.new()]

  def new(backend_model) when is_binary(backend_model),
    do: %__MODULE__{backend_model: backend_model}

  def voice(%__MODULE__{} = state, seconds)
      when is_number(seconds) and seconds >= 0 and seconds <= 1_000_000 do
    cumulative_ms = round(seconds * 1_000)
    delta = max(cumulative_ms - state.voice_ms, 0)
    {:ok, %{state | voice_ms: max(state.voice_ms, cumulative_ms)}, delta}
  end

  def voice(%__MODULE__{}, _seconds), do: {:error, :invalid_usage}

  def backend(
        %__MODULE__{} = state,
        %{
          "id" => response_id,
          "usage" => %{"input_tokens" => input, "output_tokens" => output}
        }
      )
      when is_binary(response_id) and byte_size(response_id) in 1..256 and
             is_integer(input) and input >= 0 and is_integer(output) and output >= 0 do
    if MapSet.member?(state.seen_responses, response_id) do
      {:ok, state, nil}
    else
      report = %{model: state.backend_model, input_tokens: input, output_tokens: output}
      {:ok, %{state | seen_responses: MapSet.put(state.seen_responses, response_id)}, report}
    end
  end

  def backend(%__MODULE__{}, _response), do: {:error, :invalid_usage}
end
