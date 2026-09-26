defmodule Vxpipe.Providers.OpenAI.GPTLiveRetiredTools do
  @moduledoc "Carries results from a lost session's host calls into replacement context."

  alias Vxpipe.Providers.OpenAI.{GPTLive, GPTLiveDelegation}

  defstruct calls: %{}, queued: []

  def new, do: %__MODULE__{}

  def capture(%GPTLiveDelegation{calls: calls}) do
    %__MODULE__{calls: Map.new(calls, fn {ref, call} -> {ref, call} end)}
  end

  def result(%__MODULE__{} = state, call_ref, result, ready?) do
    with {:ok, %{call_id: call_id, name: name}} <- Map.fetch(state.calls, call_ref),
         {:ok, %{"item" => %{"output" => encoded}}} <- GPTLive.tool_output(call_id, result),
         {:ok, commands} <- commands(name, encoded) do
      state = %{state | calls: Map.delete(state.calls, call_ref)}

      if ready? do
        {:ok, state, commands}
      else
        {:ok, %{state | queued: state.queued ++ commands}, []}
      end
    else
      :error -> {:error, :stale_request}
      {:error, reason} -> {:error, reason}
    end
  end

  def take_queued(%__MODULE__{} = state), do: {state.queued, %{state | queued: []}}

  defp commands(name, encoded) do
    chunks = encoded |> String.codepoints() |> Enum.chunk_every(400) |> Enum.map(&Enum.join/1)
    count = length(chunks)

    chunks
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {chunk, index}, {:ok, acc} ->
      note = "Tool #{name} finished after reconnect (#{index}/#{count}): #{chunk}"

      case GPTLive.thinking(note) do
        {:ok, command} -> {:cont, {:ok, [command | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, commands} -> {:ok, Enum.reverse(commands)}
      error -> error
    end
  end
end
