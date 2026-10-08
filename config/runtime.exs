import Config

nonempty_env = fn name ->
  case System.get_env(name) do
    nil -> nil
    value -> if String.trim(value) == "", do: nil, else: value
  end
end

worktree =
  if config_env() in [:dev, :test] do
    {metadata, _bindings} = Code.eval_file(Path.join(__DIR__, "worktree.exs"))
    metadata
  end

local_database_connection = fn ->
  port = String.to_integer(nonempty_env.("PGPORT") || "5432")

  local_socket_dir =
    Enum.find(["/var/run/postgresql", "/tmp"], &File.exists?(Path.join(&1, ".s.PGSQL.#{port}")))

  connection =
    case nonempty_env.("PGHOST") do
      nil when is_binary(local_socket_dir) -> [socket_dir: local_socket_dir]
      nil -> [hostname: "localhost"]
      "/" <> _path = socket_dir -> [socket_dir: socket_dir]
      hostname -> [hostname: hostname]
    end

  connection ++
    [
      username: nonempty_env.("PGUSER") || System.fetch_env!("USER"),
      port: port,
      password: nonempty_env.("PGPASSWORD")
    ]
end

if config_env() == :test do
  test_repo =
    case nonempty_env.("VXPIPE_TEST_DATABASE_URL") do
      nil ->
        database =
          nonempty_env.("VXPIPE_TEST_DATABASE") ||
            if(worktree, do: worktree["databases"]["test"], else: "vxpipe_test")

        local_database_connection.() ++ [database: database]

      url ->
        [url: url]
    end

  config :vxpipe_persistence, Vxpipe.Persistence.Repo, test_repo
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

{database_url, database_pool_size} =
  if config_env() == :test do
    {nil, nil}
  else
    pool_input = nonempty_env.("VXPIPE_DB_POOL_SIZE") || nonempty_env.("DB_POOL_SIZE") || "10"

    pool_size =
      case Integer.parse(pool_input) do
        {size, ""} when size > 0 -> size
        _invalid -> raise "invalid VXPIPE_DB_POOL_SIZE / DB_POOL_SIZE configuration"
      end

    url =
      nonempty_env.("VXPIPE_DB_URL") || nonempty_env.("DATABASE_URL") ||
        if(config_env() == :dev and is_nil(worktree), do: "postgres://localhost/vxpipe_dev")

    url =
      if url do
        try do
          {:ok, %URI{scheme: scheme, host: host, fragment: nil} = uri} = URI.new(url)
          true = scheme in ["postgres", "postgresql"] and is_binary(host) and host != ""

          # Ecto merges URL options last. The independent pool setting owns pool_size.
          query =
            (uri.query || "")
            |> URI.query_decoder()
            |> Enum.reject(fn {key, _value} -> key == "pool_size" end)
            |> URI.encode_query()

          normalized = URI.to_string(%{uri | query: if(query == "", do: nil, else: query)})
          _validated = Ecto.Repo.Supervisor.parse_url(normalized)
          normalized
        rescue
          _invalid -> raise "invalid VXPIPE_DB_URL / DATABASE_URL configuration"
        end
      end

    {url, pool_size}
  end

database_enabled? = not is_nil(database_url) or (config_env() == :dev and not is_nil(worktree))

if database_enabled? do
  config :vxpipe_persistence, :enabled, true

  development_repo =
    if database_url do
      defaults =
        if worktree,
          do: [
            username: nonempty_env.("PGUSER") || System.fetch_env!("USER"),
            password: nonempty_env.("PGPASSWORD")
          ],
          else: []

      defaults ++ [url: database_url, pool_size: database_pool_size]
    else
      local_database_connection.() ++
        [
          url: nil,
          database: worktree["databases"]["dev"],
          pool_size: database_pool_size
        ]
    end

  config :vxpipe_persistence, Vxpipe.Persistence.Repo, development_repo

  config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
    credential_source: {Vxpipe.Calls.ProviderCredentialSource, :configured}

  publication_recording =
    if config_env() == :dev and System.get_env("VXPIPE_RECORDING_ENABLED") in ["1", "true"] do
      :configured
    else
      :unconfigured
    end

  config :vxpipe_calls, Vxpipe.Calls,
    admin_repository: {Vxpipe.Persistence.AdminStore, Vxpipe.Persistence.Repo},
    archive_repository: {Vxpipe.Persistence.ArchiveStore, Vxpipe.Persistence.Repo},
    demo_tenant_repository: {Vxpipe.Persistence.DemoTenantStore, Vxpipe.Persistence.Repo},
    artifact_repository: {Vxpipe.Persistence.ArtifactStore, Vxpipe.Persistence.Repo},
    usage_repository: {Vxpipe.Persistence.UsageStore, Vxpipe.Persistence.Repo},
    credential_repository: {Vxpipe.Persistence.CredentialStore, Vxpipe.Persistence.Repo},
    operator_api_key_repository:
      {Vxpipe.Persistence.OperatorApiKeyStore, Vxpipe.Persistence.Repo},
    operator_login_challenge_repository:
      {Vxpipe.Persistence.OperatorLoginChallengeStore, [repo: Vxpipe.Persistence.Repo]},
    provider_credential_repository:
      {Vxpipe.Persistence.ProviderCredentialStore,
       [repo: Vxpipe.Persistence.Repo, keyring: credential_keyring]},
    provider_credential_validator: {Vxpipe.Console.ProviderCredentialValidator, []},
    telephony_service_repository:
      {Vxpipe.Persistence.TelephonyServiceStore,
       [repo: Vxpipe.Persistence.Repo, keyring: credential_keyring]},
    call_spec_repository: {Vxpipe.Persistence.CallSpecStore, Vxpipe.Persistence.Repo},
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

if database_enabled? && storage_bucket do
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
           persistence_enabled: database_enabled?
         ] ++ artifact_storage

  app_host =
    case System.get_env("APP_HOST") do
      nil -> nil
      value -> value |> String.trim() |> String.trim_trailing(".")
    end

  default_port = if worktree, do: get_in(worktree, ["ports", "console"]) || 4000, else: 4000
  port = String.to_integer(nonempty_env.("PORT") || Integer.to_string(default_port))

  if worktree do
    config :vxpipe_console, :session_cookie_name, "_vxpipe_console_#{worktree["id"]}"
  end

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
    if database_enabled? do
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

  if database_enabled? do
    room_creation = Keyword.fetch!(gateway_http, :room_creation)
    trusted_call = Keyword.fetch!(room_creation, :trusted_call)
    sample_tenant = nonempty_env.("VXPIPE_DEV_TENANT")

    config :vxpipe_console, :sample_call,
      enabled: not is_nil(sample_tenant),
      call_spec: Keyword.fetch!(trusted_call, :call_spec),
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

  check_origin =
    if console_host in ["localhost", "127.0.0.1"] do
      for host <- ["localhost", "127.0.0.1"], do: "#{console_scheme}://#{host}:#{port}"
    else
      true
    end

  console_endpoint = [url: console_url, check_origin: check_origin] ++ console_listener

  console_endpoint =
    case nonempty_env.("SECRET_KEY_BASE") do
      nil ->
        console_endpoint

      secret when byte_size(secret) >= 64 ->
        config :vxpipe_console, :operator_login_secret, secret
        Keyword.put(console_endpoint, :secret_key_base, secret)

      _invalid ->
        raise "SECRET_KEY_BASE must contain at least 64 bytes"
    end

  config :vxpipe_console, Vxpipe.Console.Endpoint, console_endpoint
end

if config_env() == :prod do
  console_host =
    case nonempty_env.("APP_HOST") do
      nil ->
        raise "APP_HOST is required for the production Console origin"

      host ->
        normalized = host |> String.downcase() |> String.trim_trailing(".")

        normalized
    end

  console_port =
    case Integer.parse(nonempty_env.("PORT") || "4000") do
      {port, ""} when port in 1..65_535 -> port
      _invalid -> raise "invalid PORT configuration"
    end

  secret_key_base =
    case nonempty_env.("SECRET_KEY_BASE") do
      secret when is_binary(secret) and byte_size(secret) >= 64 -> secret
      _invalid -> raise "SECRET_KEY_BASE must contain at least 64 bytes"
    end

  loopback_hosts = ["localhost", "127.0.0.1", "::1"]
  loopback? = console_host in loopback_hosts
  console_scheme = if loopback?, do: "http", else: "https"
  external_port = if loopback?, do: console_port, else: 443

  valid_dns_host? = fn host ->
    host
    |> String.split(".", trim: false)
    |> Enum.all?(&String.match?(&1, ~r/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/))
  end

  valid_host? =
    byte_size(console_host) <= 253 and
      case :inet.parse_address(String.to_charlist(console_host)) do
        {:ok, _address} -> true
        {:error, _reason} -> valid_dns_host?.(console_host)
      end

  unless valid_host?, do: raise("invalid APP_HOST configuration")

  listener_ip =
    case console_host do
      host when host in ["localhost", "127.0.0.1"] -> {127, 0, 0, 1}
      "::1" -> {0, 0, 0, 0, 0, 0, 0, 1}
      _public_host -> {0, 0, 0, 0}
    end

  config :vxpipe_console, Vxpipe.Console.Endpoint,
    url: [scheme: console_scheme, host: console_host, port: external_port],
    http: [ip: listener_ip, port: console_port],
    secret_key_base: secret_key_base,
    server: true

  config :vxpipe_console, :operator_login_secret, secret_key_base
end

# Child-app test runs do not load Gateway or Console; keep their runtime settings optional.
if Code.ensure_loaded?(Vxpipe.Gateway.HTTP.PublicOrigin) do
  service_public_origin =
    case Vxpipe.Gateway.HTTP.PublicOrigin.resolve(
           host: nonempty_env.("APP_HOST"),
           port: nonempty_env.("PORT"),
           tls: if(config_env() == :dev, do: nonempty_env.("VXPIPE_DEV_TLS")),
           override: nonempty_env.("TELEPHONY_HOST")
         ) do
      {:ok, origin} ->
        origin

      _invalid ->
        raise "invalid APP_HOST / PORT / VXPIPE_DEV_TLS / TELEPHONY_HOST configuration"
    end

  config :vxpipe_console, :service_public_origin, service_public_origin

  telephony_host =
    case nonempty_env.("TELEPHONY_HOST") do
      nil -> nil
      value -> URI.parse(value).host
    end

  config :vxpipe_console, :telephony_host, telephony_host

  telephony_public_base_url =
    if URI.parse(service_public_origin).scheme == "https", do: service_public_origin

  config :vxpipe_gateway, Vxpipe.Gateway.Application,
    http: [
      operator_api: [enabled: database_enabled?],
      call_spec_authoring: [enabled: database_enabled?],
      telephony: [
        enabled: not is_nil(telephony_public_base_url),
        public_base_url: telephony_public_base_url
      ]
    ]
end
