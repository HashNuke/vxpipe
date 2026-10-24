defmodule Vxpipe.Console.DatabaseRuntimeConfigurationTest do
  use ExUnit.Case, async: false

  @runtime Path.expand("../../../../../config/runtime.exs", __DIR__)
  @development Path.expand("../../../../../config/dev.exs", __DIR__)
  @test_config Path.expand("../../../../../config/test.exs", __DIR__)
  @variables ~w(VXPIPE_DB_URL DATABASE_URL VXPIPE_DB_POOL_SIZE DB_POOL_SIZE
    VXPIPE_DATABASE_URL VXPIPE_DATABASE_POOL_SIZE VXPIPE_CREDENTIAL_KEY_ID VXPIPE_CREDENTIAL_KEYS
    STORAGE_BUCKET AWS_SESSION_TOKEN VXPIPE_RECORDING_ENABLED VXPIPE_DEV_TENANT
    TELEPHONY_HOST APP_HOST PORT SECRET_KEY_BASE VXPIPE_DEV_TLS VXPIPE_MCP_RESOURCE_URL)
  @settings [{:vxpipe_gateway, Vxpipe.Gateway.Application}]

  @moduletag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    runtime = Path.join(tmp_dir, "config/runtime.exs")
    File.mkdir_p!(Path.dirname(runtime))
    File.cp!(@runtime, runtime)

    File.cp!(
      Path.join(Path.dirname(@runtime), "worktree.exs"),
      Path.join(Path.dirname(runtime), "worktree.exs")
    )

    previous = Map.new(@variables, &{&1, System.get_env(&1)})

    settings =
      Map.new(@settings, fn {app, key} -> {{app, key}, Application.fetch_env!(app, key)} end)

    Enum.each(@variables, &System.delete_env/1)
    System.put_env("APP_HOST", "console.example.test")
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

    %{runtime: runtime}
  end

  test "operator HTTP authentication is enabled with hosted persistence in development and production",
       %{runtime: runtime} do
    System.put_env("VXPIPE_DB_URL", "postgres://localhost/operator_auth_configuration")

    for environment <- [:dev, :prod] do
      configure_host(environment)

      http =
        Config.Reader.read!(runtime, env: environment)
        |> Keyword.fetch!(:vxpipe_gateway)
        |> Keyword.fetch!(Vxpipe.Gateway.Application)
        |> Keyword.fetch!(:http)

      assert http |> Keyword.get(:operator_api, []) |> Keyword.get(:enabled, false)
    end

    System.delete_env("VXPIPE_DB_URL")

    http =
      Config.Reader.read!(runtime, env: :prod)
      |> Keyword.fetch!(:vxpipe_gateway)
      |> Keyword.fetch!(Vxpipe.Gateway.Application)
      |> Keyword.fetch!(:http)

    refute http |> Keyword.get(:operator_api, []) |> Keyword.get(:enabled, false)
  end

  test "managed call cleanup and admission require durable persistence for either host", %{
    runtime: runtime
  } do
    for environment <- [:dev, :prod] do
      configure_host(environment)
      System.put_env("VXPIPE_DB_URL", "postgres://localhost/managed_runtime_configuration")

      settings =
        Config.Reader.read!(runtime, env: environment)
        |> Keyword.fetch!(:vxpipe_gateway)
        |> Keyword.fetch!(Vxpipe.Gateway.Application)

      assert settings |> Keyword.fetch!(:managed_cleanup) |> Keyword.fetch!(:enabled)
      http = Vxpipe.Gateway.Application.http_options(settings)
      assert http |> Keyword.fetch!(:call_admission) |> Keyword.fetch!(:enabled)

      assert {Vxpipe.Gateway.CallAdmission, options} =
               http |> Keyword.fetch!(:call_admission) |> Keyword.fetch!(:backend)

      assert Keyword.fetch!(options, :managed_cleanup)
      assert options |> Keyword.fetch!(:archive) |> Keyword.fetch!(:enabled)
    end

    System.delete_env("VXPIPE_DB_URL")

    settings =
      Config.Reader.read!(runtime, env: :prod)
      |> Keyword.fetch!(:vxpipe_gateway)
      |> Keyword.fetch!(Vxpipe.Gateway.Application)

    refute settings |> Keyword.fetch!(:managed_cleanup) |> Keyword.fetch!(:enabled)
  end

  test "each database alias works and the first nonblank alias wins independently", %{
    runtime: runtime
  } do
    for {url_key, pool_key} <- [
          {"VXPIPE_DB_URL", "VXPIPE_DB_POOL_SIZE"},
          {"DATABASE_URL", "DB_POOL_SIZE"}
        ] do
      System.put_env(url_key, "postgres://localhost/selected")
      System.put_env(pool_key, "7")
      assert repo(:prod, runtime) == [url: "postgres://localhost/selected", pool_size: 7]
      System.delete_env(url_key)
      System.delete_env(pool_key)
    end

    System.put_env(%{
      "VXPIPE_DB_URL" => "postgres://localhost/first",
      "DATABASE_URL" => "postgres://localhost/second",
      "VXPIPE_DB_POOL_SIZE" => "3",
      "DB_POOL_SIZE" => "9"
    })

    assert repo(:prod, runtime) == [url: "postgres://localhost/first", pool_size: 3]
    System.put_env("VXPIPE_DB_URL", "  ")
    assert repo(:prod, runtime) == [url: "postgres://localhost/second", pool_size: 3]
    System.put_env("VXPIPE_DB_POOL_SIZE", "")
    assert repo(:prod, runtime) == [url: "postgres://localhost/second", pool_size: 9]
  end

  test "blank aliases and retired settings preserve only the development default", %{
    runtime: runtime
  } do
    System.put_env(%{
      "VXPIPE_DATABASE_URL" => "postgres://localhost/retired",
      "VXPIPE_DATABASE_POOL_SIZE" => "99"
    })

    for value <- [nil, "", " \t"] do
      for key <- ~w(VXPIPE_DB_URL DATABASE_URL VXPIPE_DB_POOL_SIZE DB_POOL_SIZE) do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end

      configure_host(:dev)
      assert repo(:dev, runtime) == [url: "postgres://localhost/vxpipe_dev", pool_size: 10]
      configure_host(:prod)
      assert repo(:prod, runtime) == []
    end
  end

  test "invalid selected settings fail safely without consulting a lower-priority alias", %{
    runtime: runtime
  } do
    System.put_env("DATABASE_URL", "postgres://localhost/valid")

    for value <- [
          "https://private-user:private-password@localhost/db",
          "postgres://localhost",
          "postgres://localhost/db/other",
          "private-invalid-value"
        ] do
      System.put_env("VXPIPE_DB_URL", value)
      error = assert_raise RuntimeError, fn -> repo(:prod, runtime) end
      assert Exception.message(error) == "invalid VXPIPE_DB_URL / DATABASE_URL configuration"
    end

    System.delete_env("VXPIPE_DB_URL")
    System.put_env("DB_POOL_SIZE", "10")

    for value <- ["0", "-1", "1.5", "private-invalid-value"] do
      System.put_env("VXPIPE_DB_POOL_SIZE", value)
      error = assert_raise RuntimeError, fn -> repo(:prod, runtime) end

      assert Exception.message(error) ==
               "invalid VXPIPE_DB_POOL_SIZE / DB_POOL_SIZE configuration"
    end
  end

  test "ordinary aliases cannot replace or validate against the dedicated test database", %{
    runtime: runtime
  } do
    test_config = Config.Reader.read!(@test_config)

    before =
      test_config
      |> Config.Reader.merge(Config.Reader.read!(runtime, env: :test))
      |> Keyword.fetch!(:vxpipe_persistence)
      |> Keyword.fetch!(Vxpipe.Persistence.Repo)

    System.put_env(%{
      "VXPIPE_DB_URL" => "private-invalid-value",
      "DATABASE_URL" => "postgres://localhost/production",
      "VXPIPE_DB_POOL_SIZE" => "invalid",
      "DB_POOL_SIZE" => "1",
      "VXPIPE_DATABASE_URL" => "postgres://localhost/retired"
    })

    runtime = Config.Reader.read!(runtime, env: :test)

    merged = Config.Reader.merge(test_config, runtime)

    assert merged
           |> Keyword.fetch!(:vxpipe_persistence)
           |> Keyword.fetch!(Vxpipe.Persistence.Repo) == before

    assert Keyword.fetch!(before, :pool) == Ecto.Adapters.SQL.Sandbox
  end

  test "the independent pool setting remains authoritative in Ecto's effective configuration", %{
    runtime: runtime
  } do
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
                 repo(:prod, runtime)
               )

      assert Keyword.fetch!(effective, :database) == "selected"
      assert Keyword.fetch!(effective, :pool_size) == expected
      assert Keyword.fetch!(effective, :ssl)
    end
  end

  test "durable runtime shares the canonical OAuth issuer and resource across Console and Gateway",
       %{
         runtime: runtime
       } do
    System.put_env("VXPIPE_DB_URL", "postgres://localhost/oauth_runtime_configuration")
    configuration = Config.Reader.read!(runtime, env: :prod)
    oauth = configuration |> Keyword.fetch!(:vxpipe_console) |> Keyword.fetch!(:oauth)

    http =
      configuration
      |> Keyword.fetch!(:vxpipe_gateway)
      |> Keyword.fetch!(Vxpipe.Gateway.Application)
      |> Keyword.fetch!(:http)

    assert Keyword.fetch!(oauth, :enabled)
    assert Keyword.fetch!(oauth, :issuer) == "https://console.example.test"
    assert Keyword.fetch!(oauth, :resource) == "https://console.example.test/mcp"
    refute Keyword.fetch!(oauth, :allow_loopback_http)
    assert Keyword.fetch!(http, :oauth) == oauth
    assert Keyword.fetch!(oauth, :public_url_provider) == Vxpipe.Identity.InstallationSettings
    refute Keyword.fetch!(oauth, :resource_override)

    assert http |> Keyword.fetch!(:telephony) |> Keyword.fetch!(:public_url_provider) ==
             Vxpipe.Identity.InstallationSettings

    for key <- [:enabled, :issuer, :resource, :allowed_hosts, :allowed_origins] do
      assert http |> Keyword.fetch!(:mcp) |> Keyword.fetch!(key) == Keyword.fetch!(oauth, key)
    end

    identity = Keyword.fetch!(configuration, :vxpipe_identity)

    assert identity |> Keyword.fetch!(:dependencies) |> Map.fetch!(:installation_url_cache) ==
             Vxpipe.Identity.InstallationURLCache

    assert Keyword.fetch!(identity, :oauth_store) == Vxpipe.Persistence.OAuth.Store
    assert Keyword.fetch!(identity, :oauth_browser_store) == Vxpipe.Persistence.OAuth.Browser
  end

  test "the resource override preserves the exact mount and does not widen trusted origins", %{
    runtime: runtime
  } do
    System.put_env("VXPIPE_DB_URL", "postgres://localhost/oauth_runtime_configuration")
    resource = "https://gateway.example.test/embedded/mcp"
    System.put_env("VXPIPE_MCP_RESOURCE_URL", resource)
    configuration = Config.Reader.read!(runtime, env: :prod)
    oauth = configuration |> Keyword.fetch!(:vxpipe_console) |> Keyword.fetch!(:oauth)

    mcp =
      configuration
      |> Keyword.fetch!(:vxpipe_gateway)
      |> Keyword.fetch!(Vxpipe.Gateway.Application)
      |> Keyword.fetch!(:http)
      |> Keyword.fetch!(:mcp)

    assert Keyword.fetch!(oauth, :resource) == resource
    assert Keyword.fetch!(oauth, :resource_override)
    assert Keyword.fetch!(mcp, :resource) == resource
    assert Keyword.fetch!(oauth, :issuer) == "https://console.example.test"
    assert Keyword.fetch!(oauth, :allowed_hosts) == ["console.example.test"]
    assert Keyword.fetch!(oauth, :allowed_origins) == ["https://console.example.test"]
  end

  test "production OAuth fails closed without HTTPS while development permits local HTTP", %{
    runtime: runtime
  } do
    System.put_env("VXPIPE_DB_URL", "postgres://localhost/oauth_runtime_configuration")
    System.put_env("PORT", "4567")

    System.delete_env("APP_HOST")

    assert_raise RuntimeError, "APP_HOST is required for the production Console origin", fn ->
      Config.Reader.read!(runtime, env: :prod)
    end

    System.put_env("APP_HOST", "127.0.0.1")

    assert_raise ArgumentError, "invalid OAuth endpoint URL", fn ->
      Config.Reader.read!(runtime, env: :prod)
    end

    oauth =
      Config.Reader.read!(runtime, env: :dev)
      |> Keyword.fetch!(:vxpipe_console)
      |> Keyword.fetch!(:oauth)

    assert Keyword.fetch!(oauth, :allow_loopback_http)
    assert Keyword.fetch!(oauth, :issuer) == "http://127.0.0.1:4567"
    assert Keyword.fetch!(oauth, :resource) == "http://127.0.0.1:4567/mcp"

    System.delete_env("VXPIPE_DB_URL")
    disabled = Config.Reader.read!(runtime, env: :prod)

    refute disabled
           |> Keyword.fetch!(:vxpipe_console)
           |> Keyword.fetch!(:oauth)
           |> Keyword.fetch!(:enabled)
  end

  test "invalid production resource overrides fail without exposing their contents", %{
    runtime: runtime
  } do
    System.put_env("VXPIPE_DB_URL", "postgres://localhost/oauth_runtime_configuration")

    for resource <- [
          "http://gateway.example.test/mcp",
          "https://private-user:private-password@gateway.example.test/mcp",
          "https://gateway.example.test/mcp?token=private-marker"
        ] do
      System.put_env("VXPIPE_MCP_RESOURCE_URL", resource)

      assert_raise ArgumentError, "invalid OAuth endpoint URL", fn ->
        Config.Reader.read!(runtime, env: :prod)
      end
    end
  end

  defp repo(environment, runtime) do
    Config.Reader.read!(runtime, env: environment)
    |> Keyword.get(:vxpipe_persistence, [])
    |> Keyword.get(Vxpipe.Persistence.Repo, [])
  end

  defp configure_host(:dev), do: System.put_env("APP_HOST", "127.0.0.1")
  defp configure_host(:prod), do: System.put_env("APP_HOST", "console.example.test")
end
