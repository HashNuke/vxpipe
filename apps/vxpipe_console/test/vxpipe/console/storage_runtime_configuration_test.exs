defmodule Vxpipe.Console.StorageRuntimeConfigurationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Artifacts.CallDetailsWriter
  alias Vxpipe.Console.RecordingConfiguration

  @runtime Path.expand("../../../../../config/runtime.exs", __DIR__)
  @development Path.expand("../../../../../config/dev.exs", __DIR__)
  @variables ~w(VXPIPE_DB_URL DATABASE_URL VXPIPE_DB_POOL_SIZE DB_POOL_SIZE STORAGE_BUCKET AWS_REGION AWS_ENDPOINT AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    AWS_SESSION_TOKEN VXPIPE_RECORDING_ENABLED VXPIPE_DATABASE_URL VXPIPE_DATABASE_POOL_SIZE
    VXPIPE_RECORDING_S3_BUCKET VXPIPE_RECORDING_S3_REGION VXPIPE_RECORDING_S3_ENDPOINT
    VXPIPE_CALL_DETAILS_S3_BUCKET VXPIPE_CALL_DETAILS_S3_REGION VXPIPE_CALL_DETAILS_S3_ENDPOINT
    VXPIPE_CREDENTIAL_KEY_ID VXPIPE_CREDENTIAL_KEYS VXPIPE_DEV_MODEL_FIXTURE
    VXPIPE_DEV_SPEECH_PROFILE DEEPGRAM_API_KEY APP_HOST PORT VXPIPE_DEV_TLS)
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

    System.put_env("VXPIPE_DB_URL", "postgres://localhost/storage_runtime_test")

    on_exit(fn ->
      Enum.each(environment, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      Enum.each(previous, fn {{app, key}, value} -> Application.put_env(app, key, value) end)
    end)
  end

  test "recording, playback and publication share the configured artifact destination" do
    System.put_env("STORAGE_BUCKET", "shared-artifacts")
    System.put_env("AWS_REGION", "eu-west-2")
    System.put_env("AWS_ENDPOINT", "http://objects.example.test:9000")
    System.put_env("VXPIPE_RECORDING_ENABLED", "true")
    seed_retired_settings()

    configuration = Config.Reader.read!(@runtime, env: :dev)
    recording_settings = setting(configuration, :vxpipe_console, :recording)
    assert {:ok, recording} = RecordingConfiguration.build(recording_settings)
    {_writer, writer_options} = Keyword.fetch!(recording, :writer)
    destination = Keyword.fetch!(writer_options, :object_store_options)

    assert Keyword.fetch!(destination, :bucket) == "shared-artifacts"
    request = destination |> Keyword.fetch!(:client_options) |> Keyword.fetch!(:request_options)
    assert Keyword.fetch!(request, :region) == "eu-west-2"
    assert Keyword.fetch!(request, :host) == "objects.example.test"
    assert Keyword.fetch!(request, :port) == 9000
    assert Keyword.fetch!(request, :virtual_host) == false
    assert {:ok, ^destination} = RecordingConfiguration.playback(recording_settings)
    assert publication_destination(configuration) == destination

    recovery = setting(configuration, :vxpipe_persistence, :call_details_publication_recovery)

    assert {CallDetailsWriter, [document_store_options: ^destination]} =
             Keyword.fetch!(recovery, :publication_artifact_writer)
  end

  test "a shared bucket enables publication without enabling recording" do
    System.put_env("STORAGE_BUCKET", "shared-artifacts")
    configuration = Config.Reader.read!(@runtime, env: :dev)

    assert {:ok, [enabled: false]} =
             configuration
             |> setting(:vxpipe_console, :recording)
             |> RecordingConfiguration.build()

    assert Keyword.fetch!(publication_destination(configuration), :bucket) == "shared-artifacts"
  end

  test "absent or blank buckets ignore retired-only settings and cannot rescue enabled recording" do
    seed_retired_settings()

    for value <- [nil, "", "   "] do
      if value,
        do: System.put_env("STORAGE_BUCKET", value),
        else: System.delete_env("STORAGE_BUCKET")

      System.put_env("VXPIPE_RECORDING_ENABLED", "true")
      configuration = Config.Reader.read!(@runtime, env: :dev)
      calls = setting(configuration, :vxpipe_calls, Vxpipe.Calls)
      refute Keyword.has_key?(calls, :call_details_publication)

      assert {:error, :recording_bucket_required} =
               configuration
               |> setting(:vxpipe_console, :recording)
               |> RecordingConfiguration.build()
    end
  end

  test "an invalid shared endpoint fails safely instead of using a retired destination" do
    System.put_env("STORAGE_BUCKET", "shared-artifacts")
    System.put_env("AWS_ENDPOINT", "http://private-user:private-password@objects.example.test")
    seed_retired_settings()
    error = assert_raise RuntimeError, fn -> Config.Reader.read!(@runtime, env: :prod) end
    assert Exception.message(error) =~ "AWS_ENDPOINT"
    refute Exception.message(error) =~ "private-password"
    refute Exception.message(error) =~ "private-user"
  end

  test "runtime wires optional temporary credentials without storing their values in configuration" do
    System.put_env("AWS_SESSION_TOKEN", "runtime-session-marker")
    configuration = Config.Reader.read!(@runtime, env: :prod)
    s3 = setting(configuration, :ex_aws, :s3)
    assert Keyword.fetch!(s3, :security_token) == {:system, "AWS_SESSION_TOKEN"}
    refute inspect(configuration) =~ "runtime-session-marker"

    System.delete_env("AWS_SESSION_TOKEN")
    configuration = Config.Reader.read!(@runtime, env: :prod)
    refute Keyword.has_key?(configuration, :ex_aws)
  end

  defp seed_retired_settings do
    for prefix <- ["VXPIPE_RECORDING_S3", "VXPIPE_CALL_DETAILS_S3"] do
      System.put_env(prefix <> "_BUCKET", "retired-" <> String.downcase(prefix))
      System.put_env(prefix <> "_REGION", "ap-south-1")
      System.put_env(prefix <> "_ENDPOINT", "http://retired.example.test:9999")
    end
  end

  defp publication_destination(configuration) do
    publication =
      configuration
      |> setting(:vxpipe_calls, Vxpipe.Calls)
      |> Keyword.fetch!(:call_details_publication)

    assert {CallDetailsWriter, options} =
             Keyword.fetch!(publication, :publication_artifact_writer)

    Keyword.fetch!(options, :document_store_options)
  end

  defp setting(configuration, app, key),
    do: configuration |> Keyword.fetch!(app) |> Keyword.fetch!(key)
end
