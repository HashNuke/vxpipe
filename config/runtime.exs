import Config

if database_url = System.get_env("VXPIPE_DATABASE_URL") do
  pool_size =
    "VXPIPE_DATABASE_POOL_SIZE"
    |> System.get_env("10")
    |> String.to_integer()

  config :vxpipe_persistence, :enabled, true
  config :vxpipe_persistence, Vxpipe.Persistence.Repo, url: database_url, pool_size: pool_size

  publication_recording =
    if config_env() == :dev and System.get_env("VXPIPE_RECORDING_ENABLED") in ["1", "true"] do
      :configured
    else
      :unconfigured
    end

  config :vxpipe_calls, Vxpipe.Calls,
    archive_repository: {Vxpipe.Persistence.ArchiveStore, Vxpipe.Persistence.Repo},
    artifact_repository: {Vxpipe.Persistence.ArtifactStore, Vxpipe.Persistence.Repo},
    usage_repository: {Vxpipe.Persistence.UsageStore, Vxpipe.Persistence.Repo},
    credential_repository: {Vxpipe.Persistence.CredentialStore, Vxpipe.Persistence.Repo},
    definition_repository: {Vxpipe.Persistence.DefinitionStore, Vxpipe.Persistence.Repo},
    call_repository: {Vxpipe.Persistence.CallStore, Vxpipe.Persistence.Repo},
    call_details_inspection_repository:
      {Vxpipe.Persistence.CallDetailsInspectionStore, Vxpipe.Persistence.Repo},
    inspection_repository: {Vxpipe.Persistence.InspectionStore, Vxpipe.Persistence.Repo},
    publication_source:
      {Vxpipe.Persistence.CallDetailsSource,
       [repo: Vxpipe.Persistence.Repo, recording: publication_recording]},
    publication_repository:
      {Vxpipe.Persistence.CallDetailsPublicationStore, Vxpipe.Persistence.Repo}
end

nonempty_env = fn name ->
  case System.get_env(name) do
    nil -> nil
    value -> if String.trim(value) == "", do: nil, else: value
  end
end

call_details_bucket =
  nonempty_env.("VXPIPE_CALL_DETAILS_S3_BUCKET") ||
    nonempty_env.("VXPIPE_RECORDING_S3_BUCKET")

if database_url && call_details_bucket do
  call_details_storage = [
    bucket: call_details_bucket,
    region:
      nonempty_env.("VXPIPE_CALL_DETAILS_S3_REGION") ||
        nonempty_env.("VXPIPE_RECORDING_S3_REGION"),
    endpoint:
      nonempty_env.("VXPIPE_CALL_DETAILS_S3_ENDPOINT") ||
        nonempty_env.("VXPIPE_RECORDING_S3_ENDPOINT")
  ]

  {:ok, document_store_options} =
    Vxpipe.Artifacts.S3DocumentConfiguration.build(call_details_storage)

  publication_writer =
    {Vxpipe.Artifacts.CallDetailsWriter, [document_store_options: document_store_options]}

  config :vxpipe_calls, Vxpipe.Calls,
    call_details_publication: [
      enabled: true,
      publication_artifact_writer: publication_writer
    ]

  config :vxpipe_persistence, :call_details_publication_recovery,
    enabled: true,
    publication_artifact_writer: publication_writer
end

if config_env() == :dev do
  config :vxpipe_console, :recording,
    enabled: System.get_env("VXPIPE_RECORDING_ENABLED"),
    persistence_enabled: not is_nil(database_url),
    bucket: System.get_env("VXPIPE_RECORDING_S3_BUCKET"),
    region: System.get_env("VXPIPE_RECORDING_S3_REGION"),
    endpoint: System.get_env("VXPIPE_RECORDING_S3_ENDPOINT")

  call_engine_settings =
    Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

  agent_runtime = Keyword.fetch!(call_engine_settings, :agent_runtime)
  model_fixture = Keyword.fetch!(call_engine_settings, :model_fixture)
  speech_to_text = Keyword.fetch!(call_engine_settings, :speech_to_text)
  text_to_speech = Keyword.fetch!(call_engine_settings, :text_to_speech)

  speech_profile =
    case System.get_env("VXPIPE_DEV_SPEECH_PROFILE") do
      value when value in [nil, "", "deepgram"] -> :deepgram
      "morse" -> :morse
      _invalid -> raise "VXPIPE_DEV_SPEECH_PROFILE must be deepgram or morse"
    end

  {speech_to_text, text_to_speech} =
    case speech_profile do
      :deepgram ->
        {speech_to_text, text_to_speech}

      :morse ->
        {
          Keyword.put(speech_to_text, :enabled, false),
          Keyword.put(text_to_speech, :enabled, false)
        }
    end

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

  fixture_scenario =
    case System.get_env("VXPIPE_DEV_MODEL_FIXTURE") do
      value when value in [nil, "", "0", "false"] ->
        nil

      value when value in ["1", "true", "success"] ->
        :success

      "delay" ->
        :delay

      "failure" ->
        :failure

      "missing" ->
        :missing

      _invalid ->
        raise "VXPIPE_DEV_MODEL_FIXTURE must be success, delay, failure, missing, true, or false"
    end

  {agent_runtime, model_fixture} =
    if fixture_scenario do
      fixture_server = Vxpipe.CallEngine.Diagnostics.ModelFixture

      {
        agent_runtime
        |> Keyword.put(
          :model_provider,
          Vxpipe.CallEngine.Diagnostics.AgentRuntimeModelProvider
        )
        |> Keyword.put(:model_provider_options, fixture: fixture_server)
        |> Keyword.put(:model_provider_label, :local_fixture)
        |> Keyword.put(
          :context_compaction,
          enabled: true,
          context_window_tokens: 1_048_576,
          output_reserve_tokens: 65_536
        ),
        model_fixture
        |> Keyword.put(:enabled, true)
        |> Keyword.put(:default_scenario, fixture_scenario)
        |> Keyword.put(:delay_ms, 1_500)
        |> Keyword.put(:response, "Local fixture response.")
      }
    else
      gemini_api_key =
        fetch_required_env.("GEMINI_API_KEY", "the trusted development sample")

      config :req_llm, google_api_key: gemini_api_key

      {
        agent_runtime
        |> Keyword.put(:model_provider_options, api_key: gemini_api_key)
        |> Keyword.put(:context_compaction, enabled: true),
        model_fixture
      }
    end

  config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
    agent_runtime: agent_runtime,
    model_fixture: model_fixture,
    speech_to_text: speech_to_text,
    text_to_speech: text_to_speech

  app_host =
    case System.get_env("APP_HOST") do
      nil -> nil
      value -> value |> String.trim() |> String.trim_trailing(".")
    end

  port =
    "PORT"
    |> System.get_env("4000")
    |> String.to_integer()

  console_host = if app_host in [nil, ""], do: "localhost", else: app_host

  phoenix_tls? = System.get_env("VXPIPE_DEV_TLS") == "phoenix"

  console_scheme = if phoenix_tls?, do: "https", else: "http"

  console_url = [scheme: console_scheme, host: console_host, port: port]

  console_ip =
    cond do
      phoenix_tls? ->
        case System.fetch_env("VXPIPE_TAILSCALE_IP") do
          {:ok, address} ->
            case :inet.parse_address(String.to_charlist(address)) do
              {:ok, parsed_address} -> parsed_address
              {:error, reason} -> raise "invalid VXPIPE_TAILSCALE_IP: #{inspect(reason)}"
            end

          :error ->
            raise "VXPIPE_TAILSCALE_IP is required for Phoenix development TLS"
        end

      app_host in [nil, ""] ->
        {127, 0, 0, 1}

      true ->
        case :inet.getaddr(String.to_charlist(app_host), :inet) do
          {:ok, address} -> address
          {:error, reason} -> raise "cannot resolve APP_HOST: #{:inet.format_error(reason)}"
        end
    end

  allowed_origins =
    case app_host do
      host when host in [nil, ""] -> []
      _host -> ["#{console_scheme}://#{console_host}:#{port}"]
    end

  gateway_settings = Application.fetch_env!(:vxpipe_gateway, Vxpipe.Gateway.Application)
  gateway_http = Keyword.fetch!(gateway_settings, :http)

  gateway_http =
    if speech_profile == :morse do
      room_creation = Keyword.fetch!(gateway_http, :room_creation)
      trusted_call = Keyword.fetch!(room_creation, :trusted_call)
      definition = Keyword.fetch!(trusted_call, :definition)
      defaults = Map.fetch!(definition, :defaults)
      capabilities = Map.fetch!(defaults, :capabilities)

      capabilities =
        capabilities
        |> Map.delete(:speech_to_text)
        |> Map.put(:text_to_speech, "morse-code-tts")

      definition = Map.put(definition, :defaults, Map.put(defaults, :capabilities, capabilities))
      trusted_call = Keyword.put(trusted_call, :definition, definition)
      room_creation = Keyword.put(room_creation, :trusted_call, trusted_call)
      Keyword.put(gateway_http, :room_creation, room_creation)
    else
      gateway_http
    end

  gateway_http =
    gateway_http
    |> Keyword.put(:port, port)
    |> Keyword.update!(:cors, &Keyword.put(&1, :allowed_origins, allowed_origins))

  gateway_http =
    if database_url do
      archive = [
        enabled: true,
        writer: {Vxpipe.Persistence.EctoStorage, []},
        maximum_pending_facts: 256,
        retry_delay_ms: 250,
        drain_timeout_ms: 5_000,
        source_policy: %{"revision" => 0}
      ]

      Keyword.put(gateway_http, :call_admission,
        enabled: true,
        backend: {Vxpipe.Gateway.CallAdmission, [archive: archive]}
      )
    else
      gateway_http
    end

  config :vxpipe_gateway, Vxpipe.Gateway.Application, http: gateway_http

  if database_url do
    room_creation = Keyword.fetch!(gateway_http, :room_creation)
    trusted_call = Keyword.fetch!(room_creation, :trusted_call)

    config :vxpipe_console, :sample_call,
      enabled: true,
      definition: Keyword.fetch!(trusted_call, :definition),
      initial_variables: Keyword.fetch!(trusted_call, :initial_variables),
      tenant_name: "Vxpipe development sample",
      transfer_participant: "human-support"
  end

  console_listener =
    if phoenix_tls? do
      [
        http: false,
        https: [
          ip: console_ip,
          port: port,
          certfile: System.fetch_env!("VXPIPE_DEV_TLS_CERTFILE"),
          keyfile: System.fetch_env!("VXPIPE_DEV_TLS_KEYFILE")
        ]
      ]
    else
      [http: [ip: console_ip, port: port], https: false]
    end

  config :vxpipe_console, Vxpipe.Console.Endpoint, [url: console_url] ++ console_listener

  if fixture_scenario do
    diagnostics = Application.fetch_env!(:vxpipe_console, :diagnostics)

    config :vxpipe_console,
           :diagnostics,
           Keyword.put(
             diagnostics,
             :model_fixture,
             Vxpipe.CallEngine.Diagnostics.ModelFixture
           )
  end
end
