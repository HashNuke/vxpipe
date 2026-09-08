import Config

if config_env() == :dev do
  call_engine_settings =
    Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

  speech_to_text = Keyword.fetch!(call_engine_settings, :speech_to_text)
  text_to_speech = Keyword.fetch!(call_engine_settings, :text_to_speech)

  fetch_required_env = fn name, requirement ->
    case System.fetch_env(name) do
      {:ok, value} ->
        if String.trim(value) == "" do
          raise "#{name} is required when #{requirement} is enabled"
        else
          value
        end

      :error ->
        raise "#{name} is required when #{requirement} is enabled"
    end
  end

  deepgram_enabled =
    Keyword.fetch!(speech_to_text, :enabled) or Keyword.fetch!(text_to_speech, :enabled)

  deepgram_api_key =
    if deepgram_enabled do
      fetch_required_env.("DEEPGRAM_API_KEY", "Deepgram Flux")
    else
      nil
    end

  inject_deepgram_api_key = fn capability ->
    if Keyword.fetch!(capability, :enabled) do
      Keyword.update!(capability, :provider_options, fn provider_options ->
        Keyword.put(provider_options, :api_key, deepgram_api_key)
      end)
    else
      capability
    end
  end

  speech_to_text = inject_deepgram_api_key.(speech_to_text)
  text_to_speech = inject_deepgram_api_key.(text_to_speech)

  gemini_api_key =
    fetch_required_env.("GEMINI_API_KEY", "the trusted development sample")

  config :req_llm, google_api_key: gemini_api_key

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

  console_host = if app_host in [nil, ""], do: "localhost", else: app_host

  console_url =
    if System.get_env("VXPIPE_DEV_TLS") == "caddy" and app_host not in [nil, ""] do
      [scheme: "https", host: app_host, port: 5173]
    else
      [scheme: "http", host: console_host, port: port]
    end

  config :vxpipe_gateway, Vxpipe.Gateway.Application,
    http: [
      port: port,
      cors: [allowed_origins: allowed_origins]
    ]

  config :vxpipe_console, Vxpipe.Console.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: port],
    url: console_url
end
