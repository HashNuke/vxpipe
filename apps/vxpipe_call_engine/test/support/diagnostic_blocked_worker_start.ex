defmodule Vxpipe.CallEngine.DiagnosticBlockedWorkerStart do
  @moduledoc false

  def start_link(options, observer) do
    result = Vxpipe.CallEngine.Diagnostics.SourceWorker.start_link(options)
    send(observer, {:unresolved_worker_start, self(), result})

    receive do
      :release_worker_start -> result
    end
  end
end
