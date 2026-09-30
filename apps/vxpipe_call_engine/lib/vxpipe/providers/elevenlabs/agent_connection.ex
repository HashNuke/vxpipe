defmodule Vxpipe.Providers.ElevenLabs.AgentConnection do
  @moduledoc false
  @derive {Inspect, only: []}
  @enforce_keys [:url]
  defstruct @enforce_keys ++ [headers: []]

  def new(url) when is_binary(url) and byte_size(url) in 1..8_192 do
    case URI.new(url) do
      {:ok,
       %URI{
         scheme: "wss",
         host: "api.elevenlabs.io",
         port: 443,
         path: "/v1/convai/conversation",
         userinfo: nil,
         fragment: nil,
         query: query
       }}
      when is_binary(query) and byte_size(query) > 0 ->
        {:ok, %__MODULE__{url: url}}

      _invalid ->
        {:error, :provider_unavailable}
    end
  end

  def new(_invalid), do: {:error, :provider_unavailable}
end
