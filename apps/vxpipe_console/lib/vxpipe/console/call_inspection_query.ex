defmodule Vxpipe.Console.CallInspectionQuery do
  @moduledoc "Assembles one authorized call inspection exclusively from database-backed reads."

  alias Vxpipe.Calls.{CallDetailPage, CallReadAccess}
  alias Vxpipe.Console.{CallInspection, CallInspectionResult}

  @spec run(CallReadAccess.authority(), String.t(), keyword()) ::
          {:ok, CallInspectionResult.t()} | {:error, term()}
  def run(authority, call_id, options \\ [])
      when is_binary(call_id) and is_list(options) do
    backend = Keyword.get(options, :backend)

    with {:ok, tenant_key} <- CallReadAccess.tenant_key(authority),
         {:ok, %CallDetailPage{} = persisted} <-
           CallInspection.inspect_call(authority, call_id, [limit: 1] ++ backend_option(backend)),
         :ok <- validate_tenant(persisted, tenant_key),
         {:ok, prepared_call} <-
           CallInspection.fetch_prepared_call(
             tenant_key,
             call_id,
             backend_option(backend)
           ),
         {:ok, history} <-
           CallInspection.fetch_call_history(authority, call_id, backend_option(backend)) do
      {:ok,
       %CallInspectionResult{
         call: persisted.call,
         prepared_call: prepared_call,
         history: history,
         usage: load_usage(authority, call_id, backend)
       }}
    end
  end

  defp validate_tenant(%CallDetailPage{call: %{tenant_key: tenant_key}}, tenant_key), do: :ok
  defp validate_tenant(%CallDetailPage{}, _tenant_key), do: {:error, :call_not_found}

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
