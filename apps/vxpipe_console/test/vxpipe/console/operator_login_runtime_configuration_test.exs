defmodule Vxpipe.Console.OperatorLoginRuntimeConfigurationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Console.Endpoint

  @runtime Path.expand("../../../../../config/runtime.exs", __DIR__)
  @development Path.expand("../../../../../config/dev.exs", __DIR__)
  @variables ~w(APP_HOST PORT SECRET_KEY_BASE VXPIPE_DB_URL DATABASE_URL
    VXPIPE_CREDENTIAL_KEY_ID VXPIPE_CREDENTIAL_KEYS STORAGE_BUCKET)

  setup do
    previous = Map.new(@variables, &{&1, System.get_env(&1)})
    previous_gateway = Application.fetch_env!(:vxpipe_gateway, Vxpipe.Gateway.Application)
    Enum.each(@variables, &System.delete_env/1)

    development = Config.Reader.read!(@development)

    gateway =
      Config.Reader.merge(
        [vxpipe_gateway: [{Vxpipe.Gateway.Application, previous_gateway}]],
        development
      )
      |> Keyword.fetch!(:vxpipe_gateway)
      |> Keyword.fetch!(Vxpipe.Gateway.Application)

    Application.put_env(:vxpipe_gateway, Vxpipe.Gateway.Application, gateway)

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)

      Application.put_env(:vxpipe_gateway, Vxpipe.Gateway.Application, previous_gateway)
    end)
  end

  test "production config exposes HTTPS externally and listens on the selected internal port" do
    System.put_env("APP_HOST", "console.example.com")
    System.put_env("PORT", "4444")
    System.put_env("SECRET_KEY_BASE", String.duplicate("production-secret-", 4))

    endpoint = endpoint_config()

    assert Keyword.fetch!(endpoint, :url) ==
             [scheme: "https", host: "console.example.com", port: 443]

    assert Keyword.fetch!(endpoint, :http) == [ip: {0, 0, 0, 0}, port: 4444]
    assert Keyword.fetch!(endpoint, :server)
    assert byte_size(Keyword.fetch!(endpoint, :secret_key_base)) >= 32

    assert runtime_config()
           |> Keyword.fetch!(:vxpipe_console)
           |> Keyword.fetch!(:operator_login_secret) ==
             String.duplicate("production-secret-", 4)
  end

  test "production permits an explicit loopback HTTP origin" do
    System.put_env("APP_HOST", "127.0.0.1")
    System.put_env("PORT", "4000")
    System.put_env("SECRET_KEY_BASE", String.duplicate("production-secret-", 4))

    assert endpoint_config() |> Keyword.fetch!(:url) ==
             [scheme: "http", host: "127.0.0.1", port: 4000]
  end

  test "production rejects missing operator origin or deployment secret" do
    for {host, secret, expected} <- [
          {nil, String.duplicate("production-secret-", 4), "APP_HOST"},
          {"console.example.com", nil, "SECRET_KEY_BASE"}
        ] do
      if host, do: System.put_env("APP_HOST", host), else: System.delete_env("APP_HOST")

      if secret,
        do: System.put_env("SECRET_KEY_BASE", secret),
        else: System.delete_env("SECRET_KEY_BASE")

      error = assert_raise RuntimeError, fn -> endpoint_config() end
      assert Exception.message(error) =~ expected
    end
  end

  test "development exposes operator login only with an explicit secret" do
    runtime = Config.Reader.read!(@runtime, env: :dev)
    refute runtime |> Keyword.get(:vxpipe_console, []) |> Keyword.has_key?(:operator_login_secret)

    secret = String.duplicate("local-operator-secret-", 4)
    System.put_env("SECRET_KEY_BASE", secret)

    console =
      Config.Reader.read!(@runtime, env: :dev)
      |> Keyword.fetch!(:vxpipe_console)

    assert Keyword.fetch!(console, :operator_login_secret) == secret

    assert console
           |> Keyword.fetch!(Endpoint)
           |> Keyword.fetch!(:secret_key_base) == secret
  end

  defp endpoint_config do
    runtime_config()
    |> Keyword.fetch!(:vxpipe_console)
    |> Keyword.fetch!(Endpoint)
  end

  defp runtime_config, do: Config.Reader.read!(@runtime, env: :prod)
end
