defmodule Vxpipe.CallEngine.RoomAuthority.AgentTransfer.Restoration do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomAuthority.AgentTransfer.History
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @derive {Inspect, only: [:cause, :request]}
  @enforce_keys [:cause, :from, :request, :task, :timer]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          cause: History.failure_cause(),
          from: GenServer.from(),
          request: Request.t(),
          task: Task.t(),
          timer: reference()
        }
end
