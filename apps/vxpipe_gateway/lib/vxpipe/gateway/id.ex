defmodule Vxpipe.Gateway.Id do
  @moduledoc false

  @prefixes %{
    connection: "conn",
    session: "sess",
    telephony_leg: "tleg"
  }

  @type kind :: :connection | :session | :telephony_leg

  @spec generate(kind()) :: String.t()
  def generate(kind) when is_map_key(@prefixes, kind) do
    random =
      16
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    "#{Map.fetch!(@prefixes, kind)}_#{random}"
  end
end
