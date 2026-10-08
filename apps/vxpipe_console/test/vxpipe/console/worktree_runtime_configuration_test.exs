defmodule Vxpipe.Console.WorktreeRuntimeConfigurationTest do
  use ExUnit.Case, async: false

  @config Path.expand("../../../../../config", __DIR__)
  @variables ~w(VXPIPE_DB_URL DATABASE_URL VXPIPE_DB_POOL_SIZE DB_POOL_SIZE
    VXPIPE_TEST_DATABASE_URL VXPIPE_TEST_DATABASE PGHOST PGPORT PGUSER PGPASSWORD
    VXPIPE_CREDENTIAL_KEY_ID VXPIPE_CREDENTIAL_KEYS STORAGE_BUCKET AWS_SESSION_TOKEN
    VXPIPE_RECORDING_ENABLED VXPIPE_DEV_TENANT TELEPHONY_HOST APP_HOST PORT SECRET_KEY_BASE
    VXPIPE_DEV_TLS)
  @id String.duplicate("a1", 16)

  @moduletag :tmp_dir
  setup %{tmp_dir: tmp} do
    root = Path.expand(Path.join(tmp, "checkout"))
    File.mkdir_p!(Path.join(root, "config"))
    File.mkdir_p!(Path.join(root, ".vxpipe"))

    for file <- ~w(runtime.exs worktree.exs) do
      source = Path.join(@config, file)
      if File.exists?(source), do: File.cp!(source, Path.join([root, "config", file]))
    end

    previous = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)
    System.put_env("SECRET_KEY_BASE", String.duplicate("fixture-secret-", 6))
    System.put_env("APP_HOST", "localhost")
    gateway = Application.fetch_env!(:vxpipe_gateway, Vxpipe.Gateway.Application)

    development = Config.Reader.read!(Path.join(@config, "dev.exs"))

    settings =
      Config.Reader.merge([vxpipe_gateway: [{Vxpipe.Gateway.Application, gateway}]], development)

    Application.put_env(
      :vxpipe_gateway,
      Vxpipe.Gateway.Application,
      settings |> Keyword.fetch!(:vxpipe_gateway) |> Keyword.fetch!(Vxpipe.Gateway.Application)
    )

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      Application.put_env(:vxpipe_gateway, Vxpipe.Gateway.Application, gateway)
    end)

    metadata = %{
      "version" => 1,
      "id" => @id,
      "root" => root,
      "databases" => %{"dev" => "vxpipe_#{@id}_dev", "test" => "vxpipe_#{@id}_test"}
    }

    File.write!(Path.join(root, ".vxpipe/worktree.json"), JSON.encode!(metadata))
    %{root: root, metadata: metadata}
  end

  test "checkout metadata selects separate dev and test databases at runtime", %{root: root} do
    for environment <- [:dev, :test] do
      repo = repo(root, environment)
      assert Keyword.get(repo, :database) == "vxpipe_#{@id}_#{environment}"

      assert Keyword.get(repo, :username) ==
               (System.get_env("PGUSER") || System.fetch_env!("USER"))
    end

    assert Keyword.get(repo(root, :dev), :password) == nil
    assert Keyword.get(repo(root, :dev), :url) == nil
  end

  test "local database runtime uses the same explicit port and password as setup", %{root: root} do
    System.put_env("PGPORT", "15432")
    System.put_env("PGPASSWORD", "synthetic-password")

    for environment <- [:dev, :test] do
      assert Keyword.get(repo(root, environment), :port) == 15432
      assert Keyword.get(repo(root, environment), :password) == "synthetic-password"
    end
  end

  test "environment overrides win and test ignores development aliases", %{root: root} do
    System.put_env("VXPIPE_DB_URL", "postgres://localhost/explicit_dev")
    System.put_env("DATABASE_URL", "postgres://localhost/lower_priority")
    System.put_env("VXPIPE_TEST_DATABASE", "explicit_test")
    assert Keyword.get(repo(root, :dev), :url) == "postgres://localhost/explicit_dev"
    assert Keyword.get(repo(root, :test), :database) == "explicit_test"
    System.put_env("VXPIPE_TEST_DATABASE_URL", "postgres://localhost/url_test")
    assert Keyword.get(repo(root, :test), :url) == "postgres://localhost/url_test"
  end

  test "initialized development URL connections inherit current-role defaults rather than legacy credentials",
       %{root: root} do
    base =
      Config.Reader.read!(Path.join(@config, "dev.exs"))
      |> Keyword.fetch!(:vxpipe_persistence)
      |> Keyword.fetch!(Vxpipe.Persistence.Repo)

    System.put_env("VXPIPE_DB_URL", "postgres://localhost/explicit_dev")

    assert {:ok, effective} =
             Ecto.Repo.Supervisor.init_config(
               :runtime,
               Vxpipe.Persistence.Repo,
               :vxpipe_persistence,
               Keyword.merge(base, repo(root, :dev))
             )

    assert Keyword.get(effective, :username) == System.fetch_env!("USER")
    assert Keyword.get(effective, :password) == nil

    System.put_env(
      "VXPIPE_DB_URL",
      "postgres://fixture:synthetic@remote.example.test/explicit_dev"
    )

    assert {:ok, effective} =
             Ecto.Repo.Supervisor.init_config(
               :runtime,
               Vxpipe.Persistence.Repo,
               :vxpipe_persistence,
               Keyword.merge(base, repo(root, :dev))
             )

    assert Keyword.get(effective, :username) == "fixture"
    assert Keyword.get(effective, :password) == "synthetic"
  end

  test "no metadata retains legacy defaults and sandbox remains compile-time configuration", %{
    root: root
  } do
    File.rm!(Path.join(root, ".vxpipe/worktree.json"))
    assert Keyword.get(repo(root, :dev), :url) == "postgres://localhost/vxpipe_dev"
    assert Keyword.get(repo(root, :test), :database) == "vxpipe_test"

    sandbox =
      Config.Reader.read!(Path.join(@config, "test.exs"))
      |> Keyword.fetch!(:vxpipe_persistence)
      |> Keyword.fetch!(Vxpipe.Persistence.Repo)

    assert Keyword.get(sandbox, :pool) == Ecto.Adapters.SQL.Sandbox
    assert Keyword.get(sandbox, :pool_size) > 0
    refute Keyword.has_key?(sandbox, :database)
    refute Keyword.has_key?(sandbox, :url)
  end

  test "malformed, unsupported and copied metadata fail closed without echoing contents", %{
    root: root,
    metadata: metadata
  } do
    for invalid <- [
          "private-invalid",
          JSON.encode!(%{metadata | "version" => 2}),
          JSON.encode!(%{metadata | "root" => root <> "-other"}),
          JSON.encode!(%{metadata | "id" => "not-hex"}),
          JSON.encode!(%{metadata | "databases" => %{"dev" => "shared", "test" => "shared"}})
        ] do
      File.write!(Path.join(root, ".vxpipe/worktree.json"), invalid)
      error = assert_raise RuntimeError, fn -> repo(root, :test) end
      assert Exception.message(error) =~ "worktree metadata"
      refute Exception.message(error) =~ "private-invalid"
    end
  end

  test "development uses the assigned Console port and a checkout-specific cookie", %{
    root: root,
    metadata: metadata
  } do
    metadata =
      Map.put(metadata, "ports", %{"console" => 4501, "astro" => 4502, "storybook" => 4503})

    File.write!(Path.join(root, ".vxpipe/worktree.json"), JSON.encode!(metadata))
    runtime = Config.Reader.read!(Path.join(root, "config/runtime.exs"), env: :dev)
    console = Keyword.fetch!(runtime, :vxpipe_console)
    endpoint = Keyword.fetch!(console, Vxpipe.Console.Endpoint)
    assert endpoint |> Keyword.fetch!(:url) |> Keyword.fetch!(:port) == 4501
    assert Keyword.fetch!(console, :session_cookie_name) == "_vxpipe_console_#{@id}"
    System.put_env("PORT", "4511")

    explicit =
      Config.Reader.read!(Path.join(root, "config/runtime.exs"), env: :dev)
      |> Keyword.fetch!(:vxpipe_console)
      |> Keyword.fetch!(Vxpipe.Console.Endpoint)

    assert explicit |> Keyword.fetch!(:url) |> Keyword.fetch!(:port) == 4511

    production =
      Config.Reader.read!(Path.join(root, "config/runtime.exs"), env: :prod)
      |> Keyword.fetch!(:vxpipe_console)

    refute Keyword.has_key?(production, :session_cookie_name)
  end

  test "invalid port metadata fails before binding a development server", %{
    root: root,
    metadata: metadata
  } do
    for ports <- [
          %{"console" => 4600, "astro" => 4502, "storybook" => 4503},
          %{"console" => 4501, "astro" => 4501, "storybook" => 4503},
          %{"console" => "4501"}
        ] do
      File.write!(
        Path.join(root, ".vxpipe/worktree.json"),
        JSON.encode!(Map.put(metadata, "ports", ports))
      )

      assert_raise RuntimeError, ~r/worktree metadata/, fn -> repo(root, :dev) end
    end
  end

  test "production ignores even malformed checkout metadata", %{root: root} do
    File.write!(Path.join(root, ".vxpipe/worktree.json"), "private-invalid")
    assert repo(root, :prod) == []
  end

  defp repo(root, environment) do
    Config.Reader.read!(Path.join(root, "config/runtime.exs"), env: environment)
    |> Keyword.get(:vxpipe_persistence, [])
    |> Keyword.get(Vxpipe.Persistence.Repo, [])
  end
end
