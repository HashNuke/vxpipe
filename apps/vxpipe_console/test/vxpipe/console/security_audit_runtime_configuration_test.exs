defmodule Vxpipe.Console.SecurityAuditRuntimeConfigurationTest do
  # Regression tests for findings from the 2026-10-14 security audit.
  # See labnotes/milestones/security-audit-remediation.md.
  use ExUnit.Case, async: false

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

  # SEC-4: a development Console bound to a network address keeps the public
  # development secret_key_base from config/dev.exs, although env.sample says a
  # SECRET_KEY_BASE is required for a non-loopback host or listener.
  test "development refuses a non-loopback listener without SECRET_KEY_BASE", %{
    runtime: runtime
  } do
    System.put_env("APP_HOST", "192.0.2.10")

    assert_raise RuntimeError, ~r/SECRET_KEY_BASE/, fn ->
      Config.Reader.read!(runtime, env: :dev)
    end
  end
end
