defmodule Vxpipe.AgentRuntime.DialogueRepair do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{ConservativeInputTokenCounter, Message, ModelRequest}

  @enforce_keys [:maximum_output_tokens, :context_window_tokens]
  defstruct @enforce_keys ++ [version: :bounded_once_v1]

  @instruction "The previous final response was invalid. Return exactly one valid raw JSON " <>
                 "dialogue object with agent_mode and message. Do not use fences, extra fields " <>
                 "or tools. speaker requires nonempty text; listener permits null or nonempty text."

  def pin(:legacy, _provider, _model, _preparation), do: nil

  def pin(:mode_message_v1, provider, model, preparation) do
    %__MODULE__{
      maximum_output_tokens:
        tighter(limit(provider, model, :maximum_output_tokens), reserve(preparation)),
      context_window_tokens:
        tighter(limit(provider, model, :context_window_tokens), window(preparation))
    }
  end

  def pin(_protocol, _provider, _model, _preparation), do: nil

  def valid?(nil, :legacy), do: true

  def valid?(%__MODULE__{version: :bounded_once_v1} = policy, :mode_message_v1),
    do:
      optional_limit?(policy.maximum_output_tokens) and
        optional_limit?(policy.context_window_tokens)

  def valid?(_policy, _protocol), do: false

  def bound(request, %__MODULE__{maximum_output_tokens: maximum}) when is_integer(maximum) do
    %{request | maximum_output_tokens: tighter(request.maximum_output_tokens, maximum)}
  end

  def bound(request, _policy), do: request

  def prepare(%__MODULE__{} = policy, %ModelRequest{} = request, response) do
    maximum = request.maximum_output_tokens
    window = policy.context_window_tokens

    with true <- is_integer(maximum) and maximum > 0,
         true <- is_integer(window) and window > 0,
         {:ok, used} <- output_tokens(response.usage),
         remaining when remaining > 0 <- maximum - used,
         messages <-
           request.messages ++
             [
               Message.assistant(response.text, [], response.provider_replay),
               Message.user(@instruction, :engine)
             ],
         repair = %{request | messages: messages, maximum_output_tokens: remaining},
         {:ok, input_tokens} <- ConservativeInputTokenCounter.count(nil, repair),
         true <- input_tokens + remaining <= window do
      {:ok, repair}
    else
      _unavailable -> {:error, :invalid_dialogue}
    end
  end

  def prepare(_policy, _request, _response), do: {:error, :invalid_dialogue}

  defp output_tokens(usage) do
    case {reported_output?(usage), Map.fetch(usage, :output_tokens),
          Map.fetch(usage, "output_tokens")} do
      {true, {:ok, value}, :error} when is_integer(value) and value >= 0 -> {:ok, value}
      {true, :error, {:ok, value}} when is_integer(value) and value >= 0 -> {:ok, value}
      {true, {:ok, value}, {:ok, value}} when is_integer(value) and value >= 0 -> {:ok, value}
      _invalid -> {:error, :unknown_output_usage}
    end
  end

  defp reported_output?(usage) do
    reports =
      for key <- [:usage_reported, "usage_reported"],
          Map.has_key?(usage, key),
          do: Map.get(usage, key)

    Map.get(usage, :billing_usage_complete, true) != false and
      Map.get(usage, "billing_usage_complete", true) != false and
      reports != [] and
      Enum.all?(reports, fn
        report when is_map(report) ->
          values =
            for key <- [:output, "output"], Map.has_key?(report, key), do: Map.get(report, key)

          values != [] and Enum.all?(values, &(&1 == true))

        _other ->
          false
      end)
  end

  defp limit(provider, model, callback) do
    if Code.ensure_loaded?(provider) and function_exported?(provider, callback, 1) do
      case apply(provider, callback, [model]) do
        value when is_integer(value) and value > 0 -> value
        _missing -> nil
      end
    end
  rescue
    _error -> nil
  end

  defp reserve(%{budget: budget}), do: budget.output_reserve_tokens
  defp reserve(_preparation), do: nil
  defp window(%{budget: budget}), do: budget.context_window_tokens
  defp window(_preparation), do: nil
  defp tighter(nil, right), do: right
  defp tighter(left, nil), do: left
  defp tighter(left, right), do: min(left, right)
  defp optional_limit?(nil), do: true
  defp optional_limit?(value), do: is_integer(value) and value > 0
end
