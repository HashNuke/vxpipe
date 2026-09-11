defmodule Vxpipe.CallEngine.Id do
  @moduledoc false

  @prefixes %{
    activation: "act",
    agent_request: "areq",
    call: "call",
    command: "cmd",
    event: "evt",
    model_attempt: "matt",
    participant: "part",
    room: "room",
    room_incarnation: "rinc",
    speech_service_interval: "sint",
    stt_attempt: "satt",
    tool_attempt: "tlatt",
    transfer_attempt: "xfer",
    tts_attempt: "tatt",
    turn: "turn",
    variable_snapshot: "vsnap"
  }

  @type kind ::
          :activation
          | :agent_request
          | :call
          | :command
          | :event
          | :model_attempt
          | :participant
          | :room
          | :room_incarnation
          | :speech_service_interval
          | :stt_attempt
          | :tool_attempt
          | :transfer_attempt
          | :tts_attempt
          | :turn
          | :variable_snapshot

  @spec generate(kind()) :: String.t()
  def generate(kind) when is_map_key(@prefixes, kind) do
    random =
      16
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    "#{Map.fetch!(@prefixes, kind)}_#{random}"
  end
end
