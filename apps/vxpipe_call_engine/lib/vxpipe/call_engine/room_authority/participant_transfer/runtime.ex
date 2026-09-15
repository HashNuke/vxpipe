defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Runtime do
  @moduledoc false

  alias Vxpipe.CallEngine.{PlanStartup, ResolvedCallPlan, TextToSpeechRuntime}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @derive {Inspect, only: []}
  @enforce_keys [:plan, :startup_options]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          plan: ResolvedCallPlan.t(),
          startup_options: keyword()
        }

  def source_text_to_speech(%__MODULE__{} = runtime, %Request{} = request) do
    with true <- runtime.plan.tenant_id == request.tenant_id,
         {:ok, source} <- Map.fetch(runtime.plan.participants, request.source_definition_key),
         true <- source.participant_id == request.source_participant_id,
         source = %{source | activation_id: request.source_activation_id},
         {:ok, %TextToSpeechRuntime{} = speech} <-
           PlanStartup.participant_text_to_speech(runtime.plan, source, runtime.startup_options) do
      {:ok, speech}
    else
      _unavailable -> {:error, :source_text_to_speech_unavailable}
    end
  end
end
