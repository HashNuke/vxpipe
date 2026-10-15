defmodule Vxpipe.Console.CallInspectionQuery do
  @moduledoc "Assembles one authorized call inspection exclusively from database-backed reads."

  alias Vxpipe.Calls.{CallDetailPage, CallReadAccess}
  alias Vxpipe.Console.{CallInspection, CallInspectionResult}

  @doc "Loads tenant context and inspection under the actual user's call-read authority."
  def fetch(authority, tenant_key, call_id, options \\ []) do
    with {:ok, context} <-
           Vxpipe.Calls.fetch_operator_call(
             authority,
             tenant_key,
             call_id,
             Keyword.delete(options, :backend)
           ),
         {:ok, access} <- Vxpipe.Calls.user_call_access(authority, tenant_key),
         {:ok, result} <- run(access, call_id, options),
         true <-
           context.call.call_spec_id == result.call.call_spec_id and
             context.call.call_spec_revision == result.call.call_spec_revision do
      {:ok, context, result}
    else
      false -> {:error, :call_inspection_unavailable}
      error -> error
    end
  end

  @spec run(CallReadAccess.authority(), String.t(), keyword()) ::
          {:ok, CallInspectionResult.t()} | {:error, term()}
  def run(authority, call_id, options \\ [])
      when is_binary(call_id) and is_list(options) do
    backend = Keyword.get(options, :backend)

    with {:ok, tenant_key} <- CallReadAccess.tenant_key(authority),
         {:ok, %CallDetailPage{} = persisted} <-
           CallInspection.inspect_call(authority, call_id, [limit: 1] ++ backend_option(backend)),
         :ok <- validate_call(persisted, tenant_key, call_id),
         {:ok, prepared_call} <-
           CallInspection.fetch_prepared_call(
             tenant_key,
             call_id,
             backend_option(backend)
           ),
         :ok <- validate_plan(prepared_call, persisted.call),
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

  defp validate_call(
         %CallDetailPage{call: %{tenant_key: tenant_key, id: call_id}},
         tenant_key,
         call_id
       ), do: :ok

  defp validate_call(%CallDetailPage{}, _tenant_key, _call_id), do: {:error, :call_not_found}

  defp validate_plan(prepared, call) do
    if prepared.id == call.id and prepared.tenant_key == call.tenant_key and
         prepared.call_spec_id == call.call_spec_id and
         prepared.call_spec_revision == call.call_spec_revision,
       do: :ok,
       else: {:error, :call_inspection_unavailable}
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
