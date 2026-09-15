defmodule Vxpipe.Persistence.ProviderCredentialRuntimeTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Persistence.{CredentialKeyring, ProviderCredentialStore, Repo}

  @variables [
    "VXPIPE_DB_URL",
    "DATABASE_URL",
    "VXPIPE_DB_POOL_SIZE",
    "DB_POOL_SIZE",
    "VXPIPE_CREDENTIAL_KEY_ID",
    "VXPIPE_CREDENTIAL_KEYS",
    "VXPIPE_DATABASE_URL",
    "VXPIPE_DATABASE_POOL_SIZE",
    "STORAGE_BUCKET",
    "AWS_REGION",
    "AWS_ENDPOINT",
    "AWS_SESSION_TOKEN"
  ]
  @runtime Path.expand("../../../../../config/runtime.exs", __DIR__)

  setup do
    previous = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)
    System.put_env("VXPIPE_DB_URL", "postgres://localhost/credential_runtime_test")

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)
  end

  test "runtime injects externally provisioned keys into the tenant repository only" do
    key = :crypto.strong_rand_bytes(32)
    System.put_env("VXPIPE_CREDENTIAL_KEY_ID", "v1")
    System.put_env("VXPIPE_CREDENTIAL_KEYS", JSON.encode!(%{"v1" => Base.encode64(key)}))

    config = Config.Reader.read!(@runtime, env: :prod)
    calls = config |> Keyword.fetch!(:vxpipe_calls) |> Keyword.fetch!(Vxpipe.Calls)

    assert {ProviderCredentialStore, context} =
             Keyword.fetch!(calls, :provider_credential_repository)

    assert Keyword.fetch!(context, :repo) == Repo
    assert {:ok, "v1", ^key} = CredentialKeyring.current(Keyword.fetch!(context, :keyring))

    assert {Vxpipe.Persistence.TelephonyServiceStore, ^context} =
             Keyword.fetch!(calls, :telephony_service_repository)

    refute inspect(config) =~ Base.encode64(key)
    refute Keyword.has_key?(config, :req_llm)
  end

  test "absent keys permit credential-free boot while partial or invalid configuration fails safely" do
    config = Config.Reader.read!(@runtime, env: :prod)
    calls = config |> Keyword.fetch!(:vxpipe_calls) |> Keyword.fetch!(Vxpipe.Calls)

    assert {ProviderCredentialStore, context} =
             Keyword.fetch!(calls, :provider_credential_repository)

    assert Keyword.fetch!(context, :keyring) == nil

    System.put_env("VXPIPE_CREDENTIAL_KEYS", "private-invalid-content")
    error = assert_raise RuntimeError, fn -> Config.Reader.read!(@runtime, env: :prod) end
    refute Exception.message(error) =~ "private-invalid-content"
    assert Exception.message(error) =~ "VXPIPE_CREDENTIAL"
  end
end
