defmodule Vxpipe.CallEngine.AgentRequestTransformer do
  @moduledoc false

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  alias Jido.AI.Context
  alias Jido.AI.Reasoning.ReAct.State

  @impl true
  def transform_request(_request, %State{context: %Context{} = context}, _config, runtime_context)
      when is_map(runtime_context) do
    discarded =
      runtime_context
      |> Map.get(:vxpipe_discarded_agent_request_ids, [])
      |> MapSet.new()

    entries =
      Enum.reject(context.entries, fn entry ->
        discarded_request?(entry.refs, discarded)
      end)

    {:ok, %{messages: Context.to_messages(%{context | entries: entries})}}
  end

  def transform_request(_request, _state, _config, _runtime_context),
    do: {:error, :invalid_context}

  defp discarded_request?(refs, discarded) when is_map(refs) do
    Enum.any?([:request_id, "request_id", :vxpipe_request_id, "vxpipe_request_id"], fn key ->
      MapSet.member?(discarded, Map.get(refs, key))
    end)
  end

  defp discarded_request?(_refs, _discarded), do: false
end
