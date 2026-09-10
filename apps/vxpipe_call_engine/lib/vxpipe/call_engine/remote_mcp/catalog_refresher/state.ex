defmodule Vxpipe.CallEngine.RemoteMCP.CatalogRefresher.State do
  @moduledoc false

  @derive {Inspect,
           only: [
             :expired?,
             :last_outcome,
             :refresh_interval_ms,
             :refresh_timeout_ms,
             :stale_after_ms
           ]}
  @enforce_keys [
    :catalog_store,
    :clock,
    :expired?,
    :expiry_generation,
    :expiry_timer,
    :last_outcome,
    :last_success_at_ms,
    :refresh_interval_ms,
    :refresh_options,
    :refresh_timeout_ms,
    :refresh_timer,
    :source,
    :stale_after_ms,
    :task,
    :task_supervisor,
    :task_timeout_timer,
    :waiters
  ]
  defstruct @enforce_keys
end
