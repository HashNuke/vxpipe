defmodule Vxpipe.Providers.ElevenLabs.RealtimeAPI do
  @moduledoc "Private, bounded Realtime credential exchange; no hosted-agent resources."

  alias Vxpipe.Providers.ElevenLabs.{Realtime, RealtimeConnection}

  def connect(config, options \\ []) do
    with :ok <- Realtime.validate(config),
         {:ok, %Req.Response{status: 200, body: %{"value" => secret, "expires_at" => expiry}}} <-
           Req.post(
             "https://api.elevenlabs.io/v1/convai/realtime/client_secrets",
             [
               headers: [{"xi-api-key", config.api_key}],
               json: %{
                 "session" => Realtime.session(config),
                 "expires_after" => %{"anchor" => "created_at", "seconds" => 60}
               },
               retry: false,
               redirect: false,
               receive_timeout: 10_000,
               connect_options: [timeout: 5_000]
             ]
             |> Keyword.merge(Keyword.take(options, [:plug]))
           ),
         true <- valid_secret?(secret) and is_integer(expiry) and expiry > System.os_time(:second) do
      {:ok,
       %RealtimeConnection{
         url: "wss://api.elevenlabs.io/v1/convai/realtime",
         headers: [{"authorization", "Bearer " <> secret}]
       }}
    else
      {:ok, %Req.Response{status: status}} when status != 200 ->
        {:error, {:provider_rejected, status}}

      _failure ->
        {:error, :connection_unavailable}
    end
  rescue
    _exception -> {:error, :connection_unavailable}
  catch
    _, _reason -> {:error, :connection_unavailable}
  end

  defp valid_secret?(secret) when is_binary(secret),
    do: byte_size(secret) in 1..8_192 and Regex.match?(~r/\A[\x21-\x7E]+\z/, secret)

  defp valid_secret?(_secret), do: false
end
