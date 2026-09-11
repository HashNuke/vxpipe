defmodule Vxpipe.Artifacts.Writer.State do
  @moduledoc false

  @enforce_keys [
    :source_monitor,
    :handoff,
    :spec,
    :object_store,
    :object_store_options,
    :observer,
    :drain_timeout_ms,
    :pending,
    :progress
  ]
  defstruct @enforce_keys ++
              [
                upload: nil,
                current: nil,
                task: nil,
                operation: nil,
                closing?: false,
                drain_timer: nil,
                terminal_reason: nil
              ]
end
