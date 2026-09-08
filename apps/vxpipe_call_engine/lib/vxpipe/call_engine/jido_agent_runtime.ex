defmodule Vxpipe.CallEngine.JidoAgentRuntime do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.AgentRuntime

  alias Jido.AI.Context
  alias Vxpipe.CallEngine.Agent

  @impl true
  def ask(agent_server, query, options) do
    case Agent.ask(agent_server, query, options) do
      {:ok, request} -> {:ok, request.id}
      {:error, _reason} = error -> error
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def cancel(agent_server, request_id, reason) do
    signal =
      Jido.Signal.new!(
        "ai.react.cancel",
        %{request_id: request_id, reason: reason},
        source: "/vxpipe/call-engine"
      )

    case Jido.AgentServer.call(agent_server, signal) do
      {:ok, _agent} -> :ok
      {:error, _reason} = error -> error
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def discard_requests(_agent_server, []), do: :ok

  def discard_requests(agent_server, request_ids) when is_list(request_ids) do
    discarded = MapSet.new(request_ids)

    with {:ok, state} <- Jido.AgentServer.state(agent_server),
         %Context{} = context <- Jido.AI.get_strategy_context(state.agent),
         replacement <- discard_entries(context, discarded),
         signal <- context_replacement_signal(replacement),
         {:ok, _agent} <- Jido.AgentServer.call(agent_server, signal) do
      :ok
    else
      nil -> :ok
      {:error, _reason} = error -> error
      _other -> {:error, :unavailable}
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp discard_entries(context, discarded) do
    entries =
      Enum.reject(context.entries, fn entry ->
        discarded_request?(entry.refs, discarded)
      end)

    %{context | entries: entries}
  end

  defp discarded_request?(refs, discarded) when is_map(refs) do
    Enum.any?([:request_id, "request_id", :vxpipe_request_id, "vxpipe_request_id"], fn key ->
      MapSet.member?(discarded, Map.get(refs, key))
    end)
  end

  defp discarded_request?(_refs, _discarded), do: false

  defp context_replacement_signal(context) do
    Jido.Signal.new!(
      "ai.react.context.modify",
      %{
        op_id: "vxpipe-discard-#{System.unique_integer([:positive, :monotonic])}",
        context_ref: "default",
        operation: %{type: :replace, reason: :manual, result_context: context}
      },
      source: "/vxpipe/call-engine"
    )
  end
end
