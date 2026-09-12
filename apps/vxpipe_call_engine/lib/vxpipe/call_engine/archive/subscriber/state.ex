defmodule Vxpipe.CallEngine.Archive.Subscriber.State do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Handoff

  @enforce_keys [
    :handoff,
    :writer,
    :retry_delay_ms,
    :drain_timeout_ms,
    :pending,
    :current,
    :writer_task,
    :source_monitor,
    :closing?,
    :drain_timer,
    :archive_context,
    :source_reason,
    :source_stopped_at,
    :now,
    :completion_enqueued?,
    :completion_finished?
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          handoff: Handoff.t(),
          writer: {module(), term()},
          retry_delay_ms: non_neg_integer(),
          drain_timeout_ms: pos_integer(),
          pending: :queue.queue(term()),
          current: nil | term(),
          writer_task: nil | Task.t(),
          source_monitor: nil | reference(),
          closing?: boolean(),
          drain_timer: nil | reference(),
          archive_context: nil | map(),
          source_reason: nil | term(),
          source_stopped_at: nil | DateTime.t(),
          now: (-> DateTime.t()),
          completion_enqueued?: boolean(),
          completion_finished?: boolean()
        }
end
