defmodule Vxpipe.CallEngine.SpeechToTextActivitySource do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan

  @spec controller_agent_id(ResolvedCallPlan.t(), String.t()) :: String.t() | nil
  def controller_agent_id(%ResolvedCallPlan{} = plan, source_participant_id) do
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    case receiver.capabilities.speech_to_speech do
      %{options: %{"turn_control" => mode}}
      when source_participant_id == caller.participant_id and mode in ["external", "hybrid"] ->
        receiver.participant_id

      _other ->
        nil
    end
  end
end
