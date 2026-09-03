defmodule Vxpipe.CallEngine.Id do
  @moduledoc false

  @prefixes %{
    command: "cmd",
    room: "room",
    room_incarnation: "rinc"
  }

  @type kind :: :command | :room | :room_incarnation

  @spec generate(kind()) :: String.t()
  def generate(kind) when is_map_key(@prefixes, kind) do
    random =
      16
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    "#{Map.fetch!(@prefixes, kind)}_#{random}"
  end
end
