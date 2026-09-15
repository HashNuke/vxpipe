defmodule Vxpipe.Calls.CallPlanCompiler do
  @moduledoc false

  alias Vxpipe.CallEngine
  alias Vxpipe.Calls.{CallDurationSettings, TelephonyPlanBindings}

  @spec compile(
          Vxpipe.CallEngine.CallDefinition.t(),
          Vxpipe.CallEngine.CallInvocation.t(),
          keyword()
        ) ::
          {:ok, Vxpipe.CallEngine.ResolvedCallPlan.t()}
          | {:error,
             Vxpipe.CallEngine.Error.t()
             | :call_duration_settings_unavailable
             | :registries_unavailable}
  def compile(definition, invocation, options) when is_list(options) do
    with {:ok, registries} <- registries(options),
         {:ok, duration_options} <-
           CallDurationSettings.compiler_options(invocation.tenant_id, options),
         {:ok, plan} <-
           CallEngine.compile_definition(
             definition,
             invocation,
             registries,
             engine_options(options) ++ duration_options
           ) do
      TelephonyPlanBindings.pin(plan, options)
    end
  end

  defp registries(options) do
    configured = Application.get_env(:vxpipe_calls, Vxpipe.Calls, [])

    case Keyword.get(options, :registries, Keyword.get(configured, :registries)) do
      value when is_map(value) -> {:ok, value}
      _unavailable -> {:error, :registries_unavailable}
    end
  end

  defp engine_options(options) do
    case Keyword.fetch(options, :mcp_catalog_store) do
      {:ok, catalog_store} -> [mcp_catalog_store: catalog_store]
      :error -> []
    end
  end
end
