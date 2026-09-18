defmodule Vxpipe.Console.ProviderRuntimeConfigurationTest do
  use ExUnit.Case, async: false

  @runtime Path.expand("../../../../../config/runtime.exs", __DIR__)
  @development Path.expand("../../../../../config/dev.exs", __DIR__)
  @variables ~w(VXPIPE_DB_URL DATABASE_URL VXPIPE_DB_POOL_SIZE DB_POOL_SIZE VXPIPE_DATABASE_URL VXPIPE_DATABASE_POOL_SIZE VXPIPE_CREDENTIAL_KEY_ID
    VXPIPE_CREDENTIAL_KEYS STORAGE_BUCKET AWS_SESSION_TOKEN VXPIPE_DEV_SPEECH_PROFILE
    VXPIPE_DEV_MODEL_FIXTURE VXPIPE_DEV_TENANT DEEPGRAM_API_KEY GEMINI_API_KEY APP_HOST PORT VXPIPE_DEV_TLS
    VXPIPE_TELEPHONY_PUBLIC_BASE_URL VXPIPE_CONFIG)
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
    assert_inline_sample(context.development)
  end

  @tag :tmp_dir
  test "retired provider settings and a legacy file cannot change the inline providers",
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
    assert_inline_sample(Config.Reader.merge(context.development, configuration))
  end

  test "sample setup requires an explicit provisioned tenant selector" do
    disabled = Config.Reader.read!(@runtime, env: :dev)
    sample = disabled |> Keyword.fetch!(:vxpipe_console) |> Keyword.fetch!(:sample_call)
    refute Keyword.fetch!(sample, :enabled)

    System.put_env("VXPIPE_DEV_TENANT", "BBBBBBBBBBBBBBBB")
    enabled = Config.Reader.read!(@runtime, env: :dev)
    sample = enabled |> Keyword.fetch!(:vxpipe_console) |> Keyword.fetch!(:sample_call)
    assert Keyword.fetch!(sample, :enabled)
    assert Keyword.fetch!(sample, :tenant_key) == "BBBBBBBBBBBBBBBB"
    refute Keyword.has_key?(sample, :tenant_name)
  end

  test "platform callback origin enables tenant telephony without static credentials" do
    System.put_env("VXPIPE_TELEPHONY_PUBLIC_BASE_URL", "https://voice.example.test/voice/")
    configuration = Config.Reader.read!(@runtime, env: :dev)

    http =
      configuration
      |> Keyword.fetch!(:vxpipe_gateway)
      |> Keyword.fetch!(Vxpipe.Gateway.Application)
      |> Keyword.fetch!(:http)

    assert Keyword.fetch!(http, :telephony) == [
             enabled: true,
             public_base_url: "https://voice.example.test/voice"
           ]

    System.put_env("VXPIPE_TELEPHONY_PUBLIC_BASE_URL", "   ")
    configuration = Config.Reader.read!(@runtime, env: :dev)

    http =
      configuration
      |> Keyword.fetch!(:vxpipe_gateway)
      |> Keyword.fetch!(Vxpipe.Gateway.Application)
      |> Keyword.fetch!(:http)

    assert Keyword.fetch!(http, :telephony) == [enabled: false, public_base_url: nil]
  end

  test "an invalid callback origin fails without echoing embedded credentials" do
    System.put_env("VXPIPE_TELEPHONY_PUBLIC_BASE_URL", "https://private-value@example.test")
    error = assert_raise RuntimeError, fn -> Config.Reader.read!(@runtime, env: :dev) end
    refute Exception.message(error) =~ "private-value"
  end

  defp assert_inline_sample(configuration) do
    trusted =
      configuration
      |> Keyword.fetch!(:vxpipe_gateway)
      |> Keyword.fetch!(Vxpipe.Gateway.Application)
      |> Keyword.fetch!(:http)
      |> Keyword.fetch!(:room_creation)
      |> Keyword.fetch!(:trusted_call)

    refute Keyword.has_key?(trusted, :capability_profiles)
    call_spec = Keyword.fetch!(trusted, :call_spec)
    assert call_spec.schema_version == "20260915.01"
    assert call_spec.defaults.capabilities.speech_to_text.provider == "deepgram"
    assert call_spec.defaults.capabilities.text_to_speech.provider == "deepgram"
    assert call_spec.defaults.capabilities.model_inference.provider == "google"
  end
end
