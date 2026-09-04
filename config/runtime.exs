import Config

if config_env() == :dev do
  call_engine_settings =
    Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

  speech_to_text = Keyword.fetch!(call_engine_settings, :speech_to_text)
  text_to_speech = Keyword.fetch!(call_engine_settings, :text_to_speech)

  deepgram_enabled =
    Keyword.fetch!(speech_to_text, :enabled) or Keyword.fetch!(text_to_speech, :enabled)

  api_key =
    if deepgram_enabled do
      case System.fetch_env("DEEPGRAM_API_KEY") do
        {:ok, value} ->
          if String.trim(value) == "" do
            raise "DEEPGRAM_API_KEY is required when Deepgram Flux is enabled"
          else
            value
          end

        :error ->
          raise "DEEPGRAM_API_KEY is required when Deepgram Flux is enabled"
      end
    else
      nil
    end

  inject_api_key = fn capability ->
    if Keyword.fetch!(capability, :enabled) do
      Keyword.update!(capability, :provider_options, fn provider_options ->
        Keyword.put(provider_options, :api_key, api_key)
      end)
    else
      capability
    end
  end

  speech_to_text = inject_api_key.(speech_to_text)
  text_to_speech = inject_api_key.(text_to_speech)

  config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
    speech_to_text: speech_to_text,
    text_to_speech: text_to_speech

  app_host =
    case System.get_env("APP_HOST") do
      nil -> nil
      value -> value |> String.trim() |> String.trim_trailing(".")
    end

  allowed_origins =
    case app_host do
      host when host in [nil, ""] -> []
      host -> ["https://#{host}:5173"]
    end

  port =
    "PORT"
    |> System.get_env("4000")
    |> String.to_integer()

  config :vxpipe_gateway, Vxpipe.Gateway.Application,
    http: [
      port: port,
      cors: [allowed_origins: allowed_origins]
    ]
end
