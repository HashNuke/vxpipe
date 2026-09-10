defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.ResponseNormalizer do
  @moduledoc false

  alias Elixir.ReqLLM.Response
  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}

  @spec normalize(Response.t()) :: {:ok, ModelResponse.t()} | {:error, atom()}
  def normalize(%Response{} = response) do
    classified = Response.classify(response)

    with {:ok, calls} <- normalize_tool_calls(classified.tool_calls) do
      metadata = Response.call_metadata(response)
      usage = Map.get(metadata, :usage) || %{}

      ModelResponse.new(
        text: classified.text,
        tool_calls: calls,
        usage: usage,
        provider_metadata: Map.delete(metadata, :usage)
      )
    else
      _invalid -> {:error, :invalid_provider_response}
    end
  rescue
    _error -> {:error, :invalid_provider_response}
  catch
    _kind, _reason -> {:error, :invalid_provider_response}
  end

  defp normalize_tool_calls(calls) when is_list(calls) do
    calls
    |> Enum.reject(&provider_owned_call?/1)
    |> Enum.reduce_while({:ok, []}, fn call, {:ok, normalized} ->
      case normalize_tool_call(call) do
        {:ok, call} -> {:cont, {:ok, [call | normalized]}}
        {:error, _reason} -> {:halt, {:error, :invalid_provider_response}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, _reason} = error -> error
    end
  end

  defp normalize_tool_calls(_calls), do: {:error, :invalid_provider_response}

  defp normalize_tool_call(call) when is_map(call) do
    ToolCall.new(
      id: fetch(call, :id),
      name: fetch(call, :name),
      arguments: fetch(call, :arguments),
      provider_metadata: Elixir.ReqLLM.ToolCall.metadata(call)
    )
  end

  defp normalize_tool_call(_call), do: {:error, :invalid_provider_response}

  defp provider_owned_call?(call) do
    Elixir.ReqLLM.ToolCall.flagged_builtin?(call) or
      Elixir.ReqLLM.ToolCall.provider_native?(call)
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
