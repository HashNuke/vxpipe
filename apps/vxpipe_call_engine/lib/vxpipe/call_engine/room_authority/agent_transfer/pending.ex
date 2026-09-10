defmodule Vxpipe.CallEngine.RoomAuthority.AgentTransfer.Pending do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @derive {Inspect, only: [:deadline_ms, :request]}
  @enforce_keys [:deadline_ms, :from, :request, :task, :timer]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          deadline_ms: integer(),
          from: GenServer.from(),
          request: Request.t(),
          task: Task.t(),
          timer: reference()
        }
end
