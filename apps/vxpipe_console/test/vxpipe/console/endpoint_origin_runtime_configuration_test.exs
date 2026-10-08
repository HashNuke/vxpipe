defmodule Vxpipe.Console.EndpointOriginRuntimeConfigurationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Console.Endpoint

  @runtime Path.expand("../../../../../config/runtime.exs", __DIR__)
  @development Path.expand("../../../../../config/dev.exs", __DIR__)
  @variables ~w(APP_HOST PORT SECRET_KEY_BASE VXPIPE_DB_URL DATABASE_URL
    VXPIPE_CREDENTIAL_KEY_ID VXPIPE_CREDENTIAL_KEYS STORAGE_BUCKET
    VXPIPE_DEV_TLS VXPIPE_TAILSCALE_IP VXPIPE_DEV_TLS_CERTFILE VXPIPE_DEV_TLS_KEYFILE)

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
    previous_gateway = Application.fetch_env!(:vxpipe_gateway, Vxpipe.Gateway.Application)
    Enum.each(@variables, &System.delete_env/1)

    gateway =
      Config.Reader.merge(
        [vxpipe_gateway: [{Vxpipe.Gateway.Application, previous_gateway}]],
        Config.Reader.read!(@development)
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

    %{runtime: runtime}
  end

  test "default development accepts both loopback socket origins", %{runtime: runtime} do
    assert endpoint_config(runtime, :dev) |> Keyword.fetch!(:check_origin) ==
             ["http://localhost:4000", "http://127.0.0.1:4000"]
  end

  test "explicit loopback hosts accept both names only on the configured development port", %{
    runtime: runtime
  } do
    System.put_env("PORT", "4500")

    for host <- ["", "localhost", "127.0.0.1"] do
      System.put_env("APP_HOST", host)

      assert endpoint_config(runtime, :dev) |> Keyword.fetch!(:check_origin) ==
               ["http://localhost:4500", "http://127.0.0.1:4500"]
    end
  end

  test "Tailscale development retains the configured host origin check", %{runtime: runtime} do
    System.put_env(%{
      "APP_HOST" => "console.example.ts.net",
      "VXPIPE_DEV_TLS" => "phoenix",
      "VXPIPE_TAILSCALE_IP" => "100.64.0.1",
      "VXPIPE_DEV_TLS_CERTFILE" => "test-cert.pem",
      "VXPIPE_DEV_TLS_KEYFILE" => "test-key.pem"
    })

    endpoint = endpoint_config(runtime, :dev)

    assert Keyword.fetch!(endpoint, :url) ==
             [scheme: "https", host: "console.example.ts.net", port: 4000]

    assert Keyword.get(endpoint, :check_origin, true) == true
  end

  test "production retains the configured host origin check", %{runtime: runtime} do
    System.put_env("SECRET_KEY_BASE", String.duplicate("test-origin-secret-", 4))

    for host <- ["localhost", "127.0.0.1", "console.example.com"] do
      System.put_env("APP_HOST", host)
      assert endpoint_config(runtime, :prod) |> Keyword.get(:check_origin, true) == true
    end
  end

  defp endpoint_config(runtime, environment) do
    Config.Reader.read!(runtime, env: environment)
    |> Keyword.fetch!(:vxpipe_console)
    |> Keyword.fetch!(Endpoint)
  end
end
