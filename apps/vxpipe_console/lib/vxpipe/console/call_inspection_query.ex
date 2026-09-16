defmodule Vxpipe.Console.CallInspectionQuery do
  @moduledoc "Assembles one authorized call inspection exclusively from database-backed reads."

  alias Vxpipe.Calls.{CallDetailPage, Principal}
  alias Vxpipe.Console.{CallInspection, CallInspectionResult}

  @spec run(Principal.t(), String.t(), keyword()) ::
          {:ok, CallInspectionResult.t()} | {:error, term()}
  def run(%Principal{} = principal, call_id, options \\ [])
      when is_binary(call_id) and is_list(options) do
    backend = Keyword.get(options, :backend)

    with {:ok, %CallDetailPage{} = persisted} <-
           CallInspection.inspect_call(principal, call_id, [limit: 1] ++ backend_option(backend)),
         {:ok, prepared_call} <-
           CallInspection.fetch_prepared_call(
             persisted.call.tenant_key,
             call_id,
             backend_option(backend)
           ),
         {:ok, history} <-
           CallInspection.fetch_call_history(principal, call_id, backend_option(backend)) do
      {:ok,
       %CallInspectionResult{
         call: persisted.call,
         prepared_call: prepared_call,
         history: history,
         usage: load_usage(principal, call_id, backend)
       }}
    end
  end

  defp load_usage(principal, call_id, backend) do
    principal
    |> CallInspection.usage_report(call_id, backend_option(backend))
    |> availability()
  end

  defp availability({:ok, value}), do: {:available, value}
  defp availability({:error, reason}), do: {:unavailable, reason}

  defp backend_option(nil), do: []
  defp backend_option(backend), do: [backend: backend]
end
