defmodule Vxpipe.Calls.TestLatencyReadRepository do
  @moduledoc false

  def list_runs(context, tenant, call, limit, cursor) do
    send(context.owner, {:list_runs, tenant, call, limit, cursor})

    with :ok <- authorize(context, tenant, call) do
      {:ok, %{entries: [%{run: context.run, stored_turns: 2}], next_cursor: "run-next"}}
    end
  end

  def summarize(context, tenant, call) do
    send(context.owner, {:summarize, tenant, call})
    with :ok <- authorize(context, tenant, call), do: {:ok, context.summary}
  end

  def fetch_run(context, tenant, call, run) do
    send(context.owner, {:fetch_run, tenant, call, run})

    with :ok <- authorize(context, tenant, call) do
      if run == context.run.id,
        do: {:ok, context.run},
        else: {:error, :latency_run_not_found}
    end
  end

  def list_turns(context, tenant, call, run, limit, cursor) do
    send(context.owner, {:list_turns, tenant, call, run, limit, cursor})

    with :ok <- authorize(context, tenant, call) do
      turns = Enum.filter(context.turns, &(cursor == nil or &1.turn_id > cursor))
      {:ok, Enum.take(turns, limit)}
    end
  end

  defp authorize(%{error: error}, _tenant, _call) when error != nil, do: {:error, error}

  defp authorize(context, tenant, call) do
    if tenant == context.run.tenant_key and call == context.run.call_id,
      do: :ok,
      else: {:error, :call_not_found}
  end
end
