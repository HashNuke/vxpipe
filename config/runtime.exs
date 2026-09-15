import Config

nonempty_env = fn name ->
  case System.get_env(name) do
    nil -> nil
    value -> if String.trim(value) == "", do: nil, else: value
  end
end

credential_keyring =
  if config_env() != :test do
    case Vxpipe.Persistence.CredentialKeyring.from_config(
           nonempty_env.("VXPIPE_CREDENTIAL_KEY_ID"),
           nonempty_env.("VXPIPE_CREDENTIAL_KEYS")
         ) do
      {:ok, keyring} ->
        keyring

      {:error, _reason} ->
        raise "invalid VXPIPE_CREDENTIAL_KEY_ID / VXPIPE_CREDENTIAL_KEYS configuration"
    end
  end

database_url =
  case {config_env(), nonempty_env.("VXPIPE_DATABASE_URL")} do
    {:dev, nil} ->
      Keyword.fetch!(Application.fetch_env!(:vxpipe_persistence, Vxpipe.Persistence.Repo), :url)

    {_env, url} ->
      url
  end

if database_url do
  pool_size =
    "VXPIPE_DATABASE_POOL_SIZE"
    |> System.get_env("10")
    |> String.to_integer()

  config :vxpipe_persistence, :enabled, true
  config :vxpipe_persistence, Vxpipe.Persistence.Repo, url: database_url, pool_size: pool_size

  config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
    credential_source: {Vxpipe.Calls.ProviderCredentialSource, :configured}

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
    provider_credential_repository:
      {Vxpipe.Persistence.ProviderCredentialStore,
       [repo: Vxpipe.Persistence.Repo, keyring: credential_keyring]},
    telephony_service_repository:
      {Vxpipe.Persistence.TelephonyServiceStore,
       [repo: Vxpipe.Persistence.Repo, keyring: credential_keyring]},
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

storage_bucket = nonempty_env.("STORAGE_BUCKET")

artifact_storage = [
  bucket: storage_bucket,
  region: nonempty_env.("AWS_REGION"),
  endpoint: nonempty_env.("AWS_ENDPOINT")
]

if nonempty_env.("AWS_SESSION_TOKEN") do
  config :ex_aws, :s3, security_token: {:system, "AWS_SESSION_TOKEN"}
end

if database_url && storage_bucket do
  document_store_options =
    case Vxpipe.Artifacts.S3DocumentConfiguration.build(artifact_storage) do
      {:ok, options} ->
        options

      {:error, _reason} ->
        raise "invalid STORAGE_BUCKET / AWS_REGION / AWS_ENDPOINT configuration"
    end

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
  config :vxpipe_console,
         :recording,
         [
           enabled: System.get_env("VXPIPE_RECORDING_ENABLED"),
           persistence_enabled: not is_nil(database_url)
         ] ++ artifact_storage

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
    sample_tenant = nonempty_env.("VXPIPE_DEV_TENANT")

    config :vxpipe_console, :sample_call,
      enabled: not is_nil(sample_tenant),
      definition: Keyword.fetch!(trusted_call, :definition),
      initial_variables: Keyword.fetch!(trusted_call, :initial_variables),
      tenant_key: sample_tenant,
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
end
