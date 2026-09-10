defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantPreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.Participant.Snapshot

  @derive {Inspect, only: [:snapshot]}
  @enforce_keys [:participant_supervisor, :snapshot]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          participant_supervisor: pid(),
          snapshot: Snapshot.t()
        }
end
