defmodule Vxpipe.Gateway.TestAdmissionBindingRepository do
  @moduledoc false

  def bind_call_admission(callback, claim, incarnation),
    do: callback.(:bind, [claim, incarnation])

  def mark_call_started(callback, claim, incarnation, started_at),
    do: callback.(:started, [claim, incarnation, started_at])

  def mark_outgoing_call_started(callback, call, incarnation, started_at),
    do: callback.(:started, [call, incarnation, started_at])

  def mark_outgoing_call_failed(callback, call, reason, ended_at),
    do: callback.(:failed, [call, reason, ended_at])
end
