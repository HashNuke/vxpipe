defmodule Vxpipe.Console.DatabaseRuntimeConfigurationTest do
  use ExUnit.Case, async: false

  @runtime Path.expand("../../../../../config/runtime.exs", __DIR__)
  @development Path.expand("../../../../../config/dev.exs", __DIR__)
  @test_config Path.expand("../../../../../config/test.exs", __DIR__)
  @variables ~w(VXPIPE_DB_URL DATABASE_URL VXPIPE_DB_POOL_SIZE DB_POOL_SIZE
    VXPIPE_DATABASE_URL VXPIPE_DATABASE_POOL_SIZE VXPIPE_CREDENTIAL_KEY_ID VXPIPE_CREDENTIAL_KEYS
    STORAGE_BUCKET AWS_SESSION_TOKEN VXPIPE_RECORDING_ENABLED VXPIPE_DEV_TENANT
    VXPIPE_TELEPHONY_PUBLIC_BASE_URL APP_HOST PORT SECRET_KEY_BASE VXPIPE_DEV_TLS)
  @settings [{:vxpipe_gateway, Vxpipe.Gateway.Application}]

  setup do
    previous = Map.new(@variables, &{&1, System.get_env(&1)})

    settings =
      Map.new(@settings, fn {app, key} -> {{app, key}, Application.fetch_env!(app, key)} end)

    Enum.each(@variables, &System.delete_env/1)
    System.put_env("APP_HOST", "127.0.0.1")
    System.put_env("SECRET_KEY_BASE", String.duplicate("runtime-test-secret-", 4))
    development = Config.Reader.read!(@development)

    for {app, key} <- @settings do
      merged =
        Config.Reader.merge([{app, [{key, Application.fetch_env!(app, key)}]}], development)

      Application.put_env(app, key, merged |> Keyword.fetch!(app) |> Keyword.fetch!(key))
    end

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      Enum.each(settings, fn {{app, key}, value} -> Application.put_env(app, key, value) end)
    end)
  end

  test "operator HTTP authentication is enabled with hosted persistence in development and production" do
    System.put_env("VXPIPE_DB_URL", "postgres://localhost/operator_auth_configuration")

    for environment <- [:dev, :prod] do
      http =
        Config.Reader.read!(@runtime, env: environment)
        |> Keyword.fetch!(:vxpipe_gateway)
        |> Keyword.fetch!(Vxpipe.Gateway.Application)
        |> Keyword.fetch!(:http)

      assert http |> Keyword.get(:operator_api, []) |> Keyword.get(:enabled, false)
    end

    System.delete_env("VXPIPE_DB_URL")

    http =
      Config.Reader.read!(@runtime, env: :prod)
      |> Keyword.fetch!(:vxpipe_gateway)
      |> Keyword.fetch!(Vxpipe.Gateway.Application)
      |> Keyword.fetch!(:http)

    refute http |> Keyword.get(:operator_api, []) |> Keyword.get(:enabled, false)
  end

  test "each database alias works and the first nonblank alias wins independently" do
    for {url_key, pool_key} <- [
          {"VXPIPE_DB_URL", "VXPIPE_DB_POOL_SIZE"},
          {"DATABASE_URL", "DB_POOL_SIZE"}
        ] do
      System.put_env(url_key, "postgres://localhost/selected")
      System.put_env(pool_key, "7")
      assert repo(:prod) == [url: "postgres://localhost/selected", pool_size: 7]
      System.delete_env(url_key)
      System.delete_env(pool_key)
    end

    System.put_env(%{
      "VXPIPE_DB_URL" => "postgres://localhost/first",
      "DATABASE_URL" => "postgres://localhost/second",
      "VXPIPE_DB_POOL_SIZE" => "3",
      "DB_POOL_SIZE" => "9"
    })

    assert repo(:prod) == [url: "postgres://localhost/first", pool_size: 3]
    System.put_env("VXPIPE_DB_URL", "  ")
    assert repo(:prod) == [url: "postgres://localhost/second", pool_size: 3]
    System.put_env("VXPIPE_DB_POOL_SIZE", "")
    assert repo(:prod) == [url: "postgres://localhost/second", pool_size: 9]
  end

  test "blank aliases and retired settings preserve only the development default" do
    System.put_env(%{
      "VXPIPE_DATABASE_URL" => "postgres://localhost/retired",
      "VXPIPE_DATABASE_POOL_SIZE" => "99"
    })

    for value <- [nil, "", " \t"] do
      for key <- ~w(VXPIPE_DB_URL DATABASE_URL VXPIPE_DB_POOL_SIZE DB_POOL_SIZE) do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end

      assert repo(:dev) == [url: "postgres://localhost/vxpipe_dev", pool_size: 10]
      assert repo(:prod) == []
    end
  end

  test "invalid selected settings fail safely without consulting a lower-priority alias" do
    System.put_env("DATABASE_URL", "postgres://localhost/valid")

    for value <- [
          "https://private-user:private-password@localhost/db",
          "postgres://localhost",
          "postgres://localhost/db/other",
          "private-invalid-value"
        ] do
      System.put_env("VXPIPE_DB_URL", value)
      error = assert_raise RuntimeError, fn -> repo(:prod) end
      assert Exception.message(error) == "invalid VXPIPE_DB_URL / DATABASE_URL configuration"
    end

    System.delete_env("VXPIPE_DB_URL")
    System.put_env("DB_POOL_SIZE", "10")

    for value <- ["0", "-1", "1.5", "private-invalid-value"] do
      System.put_env("VXPIPE_DB_POOL_SIZE", value)
      error = assert_raise RuntimeError, fn -> repo(:prod) end

      assert Exception.message(error) ==
               "invalid VXPIPE_DB_POOL_SIZE / DB_POOL_SIZE configuration"
    end
  end

  test "ordinary aliases cannot replace or validate against the dedicated test database" do
    test_config = Config.Reader.read!(@test_config)

    before =
      test_config
      |> Keyword.fetch!(:vxpipe_persistence)
      |> Keyword.fetch!(Vxpipe.Persistence.Repo)

    System.put_env(%{
      "VXPIPE_DB_URL" => "private-invalid-value",
      "DATABASE_URL" => "postgres://localhost/production",
      "VXPIPE_DB_POOL_SIZE" => "invalid",
      "DB_POOL_SIZE" => "1",
      "VXPIPE_DATABASE_URL" => "postgres://localhost/retired"
    })

    runtime = Config.Reader.read!(@runtime, env: :test)

    assert runtime
           |> Keyword.get(:vxpipe_persistence, [])
           |> Keyword.get(Vxpipe.Persistence.Repo, []) == []

    merged = Config.Reader.merge(test_config, runtime)

    assert merged
           |> Keyword.fetch!(:vxpipe_persistence)
           |> Keyword.fetch!(Vxpipe.Persistence.Repo) == before

    assert Keyword.fetch!(before, :pool) == Ecto.Adapters.SQL.Sandbox
  end

  test "the independent pool setting remains authoritative in Ecto's effective configuration" do
    System.put_env("VXPIPE_DB_URL", "postgres://localhost/selected?pool_size=1&ssl=true")

    for {selected, expected} <- [{nil, 10}, {"7", 7}] do
      if selected,
        do: System.put_env("DB_POOL_SIZE", selected),
        else: System.delete_env("DB_POOL_SIZE")

      assert {:ok, effective} =
               Ecto.Repo.Supervisor.init_config(
                 :runtime,
                 Vxpipe.Persistence.Repo,
                 :vxpipe_persistence,
                 repo(:prod)
               )

      assert Keyword.fetch!(effective, :database) == "selected"
      assert Keyword.fetch!(effective, :pool_size) == expected
      assert Keyword.fetch!(effective, :ssl)
    end
  end

  defp repo(environment) do
    Config.Reader.read!(@runtime, env: environment)
    |> Keyword.get(:vxpipe_persistence, [])
    |> Keyword.get(Vxpipe.Persistence.Repo, [])
  end
end
