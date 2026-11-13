defmodule Vxpipe.Console.ProviderRuntimeConfigurationTest do
  use ExUnit.Case, async: false

  @runtime Path.expand("../../../../../config/runtime.exs", __DIR__)
  @development Path.expand("../../../../../config/dev.exs", __DIR__)
  @variables ~w(VXPIPE_DB_URL DATABASE_URL VXPIPE_DB_POOL_SIZE DB_POOL_SIZE VXPIPE_DATABASE_URL VXPIPE_DATABASE_POOL_SIZE VXPIPE_CREDENTIAL_KEY_ID
    VXPIPE_CREDENTIAL_KEYS STORAGE_BUCKET AWS_SESSION_TOKEN VXPIPE_DEV_SPEECH_PROFILE
    VXPIPE_DEV_MODEL_FIXTURE VXPIPE_DEV_TENANT DEEPGRAM_API_KEY GEMINI_API_KEY APP_HOST PORT VXPIPE_DEV_TLS
    TELEPHONY_HOST VXPIPE_CONFIG SECRET_KEY_BASE MORSE_CODE_API_BASE_URL)
  @settings [
    {:vxpipe_call_engine, Vxpipe.CallEngine.Application},
    {:vxpipe_gateway, Vxpipe.Gateway.Application},
    {:vxpipe_console, :diagnostics}
  ]

  setup do
    environment = Map.new(@variables, &{&1, System.get_env(&1)})

    previous =
      Map.new(@settings, fn {app, key} -> {{app, key}, Application.get_env(app, key)} end)

    Enum.each(@variables, &System.delete_env/1)
    development = Config.Reader.read!(@development)

    for {app, key} <- @settings do
      override = development |> Keyword.fetch!(app) |> Keyword.fetch!(key)
      current = Application.get_env(app, key, [])
      merged = Config.Reader.merge([{app, [{key, current}]}], [{app, [{key, override}]}])
      Application.put_env(app, key, merged |> Keyword.fetch!(app) |> Keyword.fetch!(key))
    end

    System.put_env("VXPIPE_DB_URL", "postgres://localhost/provider_runtime_test")

    on_exit(fn ->
      Enum.each(environment, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      Enum.each(previous, fn {{app, key}, value} -> Application.put_env(app, key, value) end)
    end)

    [development: development]
  end

  test "development boot requires no provider environment credential", context do
    configuration = Config.Reader.read!(@runtime, env: :dev)
    refute Keyword.has_key?(configuration, :req_llm)
    assert_no_configured_speech(context.development)
  end

  test "Morse runtime configuration defaults locally and requires an explicit HTTPS production origin" do
    development = Config.Reader.read!(@runtime, env: :dev)
    local = development |> Keyword.fetch!(:vxpipe_providers) |> Keyword.fetch!(:morse_code_api)
    assert local == [base_url: "http://127.0.0.1:8787", allow_http?: true]

    System.put_env("APP_HOST", "console.example.test")
    System.put_env("SECRET_KEY_BASE", String.duplicate("synthetic-runtime-secret-", 4))
    production = Config.Reader.read!(@runtime, env: :prod)
    missing = production |> Keyword.fetch!(:vxpipe_providers) |> Keyword.fetch!(:morse_code_api)
    assert missing == [base_url: nil, allow_http?: false]

    previous = Application.fetch_env(:vxpipe_providers, :morse_code_api)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:vxpipe_providers, :morse_code_api, value)
        :error -> Application.delete_env(:vxpipe_providers, :morse_code_api)
      end
    end)

    Application.put_env(:vxpipe_providers, :morse_code_api, missing)

    assert {:error, :endpoint_not_configured} =
             Vxpipe.Providers.MorseCodeApi.TTS.new(api_key: "synthetic")

    System.put_env("MORSE_CODE_API_BASE_URL", "https://morse.example.test/")
    configured = Config.Reader.read!(@runtime, env: :prod)
    hosted = configured |> Keyword.fetch!(:vxpipe_providers) |> Keyword.fetch!(:morse_code_api)
    Application.put_env(:vxpipe_providers, :morse_code_api, hosted)
    assert {:ok, selected} = Vxpipe.Providers.MorseCodeApi.TTS.new(api_key: "synthetic")
    assert selected.endpoint == "https://morse.example.test"
    assert {:ok, endpoint} = Vxpipe.Providers.MorseCodeApi.Endpoint.configured()
    assert endpoint.websocket == "wss://morse.example.test"
  end

  @tag :tmp_dir
  test "retired provider settings and a legacy file cannot configure speech providers",
       context do
    legacy = Path.join(context.tmp_dir, "vxpipe.toml")
    File.write!(legacy, "[malformed legacy-private-marker")
    System.put_env("VXPIPE_CONFIG", legacy)
    System.put_env("VXPIPE_DEV_SPEECH_PROFILE", "morse")
    System.put_env("VXPIPE_DEV_MODEL_FIXTURE", "true")
    System.put_env("DEEPGRAM_API_KEY", "retired-private-marker")
    System.put_env("GEMINI_API_KEY", "retired-private-marker")

    configuration = Config.Reader.read!(@runtime, env: :dev)
    refute inspect(configuration) =~ "retired-private-marker"
    refute inspect(configuration) =~ "legacy-private-marker"
    assert_no_configured_speech(Config.Reader.merge(context.development, configuration))
  end

  test "a legacy development tenant selector does not install an application-configured call" do
    System.put_env("VXPIPE_DEV_TENANT", "BBBBBBBBBBBBBBBB")
    configuration = Config.Reader.read!(@runtime, env: :dev)
    console = Keyword.fetch!(configuration, :vxpipe_console)
    refute Keyword.has_key?(console, :sample_call)
  end

  test "platform callback origin enables tenant telephony without static credentials" do
    System.put_env("TELEPHONY_HOST", "https://voice.example.test/voice/")
    configuration = Config.Reader.read!(@runtime, env: :dev)

    http =
      configuration
      |> Keyword.fetch!(:vxpipe_gateway)
      |> Keyword.fetch!(Vxpipe.Gateway.Application)
      |> Keyword.fetch!(:http)

    assert Keyword.fetch!(http, :telephony) == [
             enabled: true,
             public_base_url: "https://voice.example.test/voice",
             public_url_provider: nil
           ]

    assert configuration
           |> Keyword.fetch!(:vxpipe_console)
           |> Keyword.fetch!(:service_public_origin) ==
             "https://voice.example.test/voice"

    System.put_env("TELEPHONY_HOST", "   ")
    configuration = Config.Reader.read!(@runtime, env: :dev)

    http =
      configuration
      |> Keyword.fetch!(:vxpipe_gateway)
      |> Keyword.fetch!(Vxpipe.Gateway.Application)
      |> Keyword.fetch!(:http)

    assert Keyword.fetch!(http, :telephony) == [
             enabled: true,
             public_base_url: nil,
             public_url_provider: Vxpipe.Identity.InstallationSettings
           ]

    assert configuration
           |> Keyword.fetch!(:vxpipe_console)
           |> Keyword.fetch!(:service_public_origin) ==
             "http://localhost:4000"
  end

  test "a public application host supplies the shared HTTPS callback origin" do
    System.put_env("APP_HOST", "192.0.2.15")
    System.put_env("SECRET_KEY_BASE", String.duplicate("test-only-", 8))
    configuration = Config.Reader.read!(@runtime, env: :dev)

    assert configuration
           |> Keyword.fetch!(:vxpipe_console)
           |> Keyword.fetch!(:service_public_origin) ==
             "https://192.0.2.15"

    http =
      configuration
      |> Keyword.fetch!(:vxpipe_gateway)
      |> Keyword.fetch!(Vxpipe.Gateway.Application)
      |> Keyword.fetch!(:http)

    assert Keyword.fetch!(http, :telephony) == [
             enabled: true,
             public_base_url: "https://192.0.2.15",
             public_url_provider: Vxpipe.Identity.InstallationSettings
           ]
  end

  test "an invalid callback origin fails without echoing embedded credentials" do
    System.put_env("TELEPHONY_HOST", "https://private-value@example.test")
    error = assert_raise RuntimeError, fn -> Config.Reader.read!(@runtime, env: :dev) end
    refute Exception.message(error) =~ "private-value"
  end

  defp assert_no_configured_speech(configuration) do
    engine =
      configuration
      |> Keyword.fetch!(:vxpipe_call_engine)
      |> Keyword.fetch!(Vxpipe.CallEngine.Application)

    for kind <- [:speech_to_text, :text_to_speech, :speech_to_speech] do
      refute Keyword.has_key?(engine, kind)
    end

    http =
      configuration
      |> Keyword.fetch!(:vxpipe_gateway)
      |> Keyword.fetch!(Vxpipe.Gateway.Application)
      |> Keyword.fetch!(:http)

    refute http |> Keyword.get(:room_creation, []) |> Keyword.has_key?(:trusted_call)
  end
end
