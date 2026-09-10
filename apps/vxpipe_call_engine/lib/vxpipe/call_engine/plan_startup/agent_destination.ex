defmodule Vxpipe.CallEngine.PlanStartup.AgentDestination do
  @moduledoc false

  alias Vxpipe.CallEngine.Command.JoinParticipant
  alias Vxpipe.CallEngine.ResolvedCallPlan.Participant
  alias Vxpipe.CallEngine.TextToSpeechRuntime

  @derive {Inspect, only: [:participant]}
  @enforce_keys [:participant, :command, :agent_activation, :text_to_speech]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          participant: Participant.t(),
          command: JoinParticipant.t(),
          agent_activation: keyword(),
          text_to_speech: nil | TextToSpeechRuntime.t()
        }
end
