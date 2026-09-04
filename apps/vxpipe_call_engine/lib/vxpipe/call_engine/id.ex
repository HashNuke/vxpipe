defmodule Vxpipe.CallEngine.Id do
  @moduledoc false

  @prefixes %{
    command: "cmd",
    event: "evt",
    participant: "part",
    room: "room",
    room_incarnation: "rinc",
    turn: "turn"
  }

  @type kind :: :command | :event | :participant | :room | :room_incarnation | :turn

  @spec generate(kind()) :: String.t()
  def generate(kind) when is_map_key(@prefixes, kind) do
    random =
      16
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    "#{Map.fetch!(@prefixes, kind)}_#{random}"
  end
end
