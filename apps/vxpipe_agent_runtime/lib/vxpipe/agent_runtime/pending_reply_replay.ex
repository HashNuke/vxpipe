defmodule Vxpipe.AgentRuntime.PendingReplyReplay do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{Dialogue, Message, ModelResponse}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM.{ChatReasoningReplay, Config}

  @derive {Inspect, only: []}
  @enforce_keys [:dialogue_digest, :replay]
  defstruct @enforce_keys

  @type t :: %__MODULE__{dialogue_digest: binary(), replay: map()}

  def prepare(%ModelResponse{} = response, %Dialogue{} = dialogue, %{
        model: %Config{model: model},
        history_mode: :host_settled
      }) do
    case ChatReasoningReplay.settlement_candidate(response, model) do
      {:ok, replay} ->
        %__MODULE__{
          dialogue_digest: digest(dialogue.agent_mode, dialogue.message),
          replay: replay
        }

      :none ->
        nil
    end
  end

  def prepare(_response, _output, _config), do: nil

  def settle(%__MODULE__{} = pending, %Message{} = message) do
    with {:ok, %{"agent_mode" => mode, "message" => text}} <- JSON.decode(message.content),
         true <- pending.dialogue_digest == digest(mode, text) do
      ChatReasoningReplay.bind_settled(pending.replay, message)
    else
      _mismatch -> message
    end
  end

  def settle(_pending, message), do: message

  defp digest(mode, text) do
    :crypto.hash(:sha256, :erlang.term_to_binary({to_string(mode), text}, [:deterministic]))
  end
end
