defmodule Vxpipe.Console.CallInspectionQuery do
  @moduledoc "Assembles one authorized call inspection exclusively from database-backed reads."

  alias Vxpipe.Calls.{CallDetailPage, Principal}
  alias Vxpipe.Console.{CallInspection, CallInspectionResult}

  @default_limit 50

  @spec run(Principal.t(), String.t(), keyword()) ::
          {:ok, CallInspectionResult.t()} | {:error, term()}
  def run(%Principal{} = principal, call_id, options \\ [])
      when is_binary(call_id) and is_list(options) do
    backend = Keyword.get(options, :backend)
    inspection_options = inspection_options(options, backend)

    with {:ok, %CallDetailPage{} = persisted} <-
           CallInspection.inspect_call(principal, call_id, inspection_options) do
      {:ok,
       %CallInspectionResult{
         persisted: persisted,
         definition: load_definition(persisted, backend),
         usage: load_usage(principal, call_id, backend),
         as_of: Keyword.get_lazy(options, :now, &DateTime.utc_now/0)
       }}
    end
  end

  defp inspection_options(options, backend) do
    options
    |> Keyword.take([:cursor, :limit])
    |> Keyword.put_new(:limit, @default_limit)
    |> Keyword.put(:backend, backend)
  end

  defp load_definition(%CallDetailPage{call: call}, backend) do
    call.tenant_key
    |> CallInspection.fetch_definition(
      call.definition_id,
      call.definition_revision,
      backend_option(backend)
    )
    |> availability()
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
