defmodule Vxpipe.CallEngine.RemoteMCP.CatalogRefresher.Options do
  @moduledoc false

  alias Vxpipe.CallEngine.RemoteMCP.{ApplicationConfiguration, CatalogStore}

  @default_refresh_interval_ms 60_000
  @default_refresh_timeout_ms 30_000
  @default_stale_after_ms 300_000
  @default_task_supervisor Vxpipe.CallEngine.RemoteMCP.CatalogRefreshTaskSupervisor

  @derive {Inspect, except: [:clock, :refresh_options, :source]}
  @enforce_keys [
    :catalog_store,
    :clock,
    :refresh_interval_ms,
    :refresh_options,
    :refresh_timeout_ms,
    :source,
    :stale_after_ms,
    :task_supervisor
  ]
  defstruct @enforce_keys

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_configuration}
  def new(options) when is_list(options) do
    with {:ok, options} <-
           Keyword.validate(options, [
             :catalog_store,
             :clock,
             :connection_provider,
             :maximum_concurrency,
             :name,
             :protocol,
             :refresh_interval_ms,
             :refresh_timeout_ms,
             :source,
             :stale_after_ms,
             :task_supervisor
           ]),
         {:ok, source} <- validate_source(Keyword.get(options, :source)),
         clock when is_function(clock, 0) <-
           Keyword.get(options, :clock, fn -> System.monotonic_time(:millisecond) end),
         refresh_interval_ms when is_integer(refresh_interval_ms) and refresh_interval_ms > 0 <-
           Keyword.get(options, :refresh_interval_ms, @default_refresh_interval_ms),
         refresh_timeout_ms when is_integer(refresh_timeout_ms) and refresh_timeout_ms > 0 <-
           Keyword.get(options, :refresh_timeout_ms, @default_refresh_timeout_ms),
         stale_after_ms
         when is_integer(stale_after_ms) and stale_after_ms > refresh_interval_ms <-
           Keyword.get(options, :stale_after_ms, @default_stale_after_ms) do
      catalog_store = Keyword.get(options, :catalog_store, CatalogStore)

      {:ok,
       %__MODULE__{
         catalog_store: catalog_store,
         clock: clock,
         refresh_interval_ms: refresh_interval_ms,
         refresh_options:
           Keyword.take(options, [:connection_provider, :maximum_concurrency, :protocol]) ++
             [catalog_store: catalog_store],
         refresh_timeout_ms: refresh_timeout_ms,
         source: source,
         stale_after_ms: stale_after_ms,
         task_supervisor: Keyword.get(options, :task_supervisor, @default_task_supervisor)
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  @type t :: %__MODULE__{
          catalog_store: GenServer.server(),
          clock: (-> integer()),
          refresh_interval_ms: pos_integer(),
          refresh_options: keyword(),
          refresh_timeout_ms: pos_integer(),
          source: {module(), keyword()},
          stale_after_ms: pos_integer(),
          task_supervisor: Supervisor.supervisor()
        }

  defp validate_source(nil), do: validate_source({ApplicationConfiguration, []})

  defp validate_source({module, options}) when is_atom(module) and is_list(options) do
    if Code.ensure_loaded?(module) and function_exported?(module, :fetch, 1),
      do: {:ok, {module, options}},
      else: {:error, :invalid_source}
  end

  defp validate_source(_source), do: {:error, :invalid_source}
end
