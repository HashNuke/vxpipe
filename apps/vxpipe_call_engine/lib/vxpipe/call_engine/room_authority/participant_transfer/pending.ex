defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Pending do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @derive {Inspect, only: [:attempt_id, :deadline_ms, :request]}
  @enforce_keys [:attempt_id, :deadline_ms, :from, :request, :task, :timer]
  defstruct @enforce_keys ++
              [
                accepted?: false,
                briefing: :not_required,
                briefing_request: nil,
                destination_connection_id: nil,
                media_ready?: false,
                preparation: nil
              ]

  @type t :: %__MODULE__{
          attempt_id: String.t(),
          deadline_ms: integer(),
          from: GenServer.from(),
          request: Request.t(),
          task: Task.t(),
          timer: reference(),
          accepted?: boolean(),
          briefing: :not_required | :waiting | :playing | :completed,
          briefing_request: nil | Vxpipe.CallEngine.TextToSpeechRequest.t(),
          destination_connection_id: nil | String.t(),
          media_ready?: boolean(),
          preparation:
            nil
            | Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Preparation.t()
            | Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.HumanPreparation.t()
        }
end
