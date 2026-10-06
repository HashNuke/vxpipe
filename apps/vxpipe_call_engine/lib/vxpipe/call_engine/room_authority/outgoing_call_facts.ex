defmodule Vxpipe.CallEngine.RoomAuthority.OutgoingCallFacts do
  @moduledoc false
  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Id

  def emit(state, kind, outcome \\ nil) do
    payload = if outcome, do: %{"outcome" => Atom.to_string(outcome)}, else: %{}

    recorder =
      Recorder.internal_fact(state.archive_recorder, kind,
        id: Id.generate(:event),
        occurred_at: DateTime.utc_now(),
        payload: payload
      )

    %{state | archive_recorder: recorder}
  end
end
