defmodule Vxpipe.CallEngine.TestElevenLabsRealtimeRoomPing do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}

  @impl true
  def definition do
    %Definition{
      name: "ping",
      description: "Reply to a ping in the compiled ElevenLabs room test.",
      parameters: %{"type" => "object", "properties" => %{}, "additionalProperties" => false}
    }
  end

  @impl true
  def execute(arguments, %Context{}) when map_size(arguments) == 0,
    do: {:ok, %{"pong" => true}}
end
