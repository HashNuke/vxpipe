defmodule Vxpipe.Persistence.ProviderCredentialReencryptionTaskTest do
  use Vxpipe.Persistence.DataCase, async: false

  import ExUnit.CaptureIO

  alias Vxpipe.Calls.{Administration, ProviderCredentials}
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, ProviderCredentialStore}

  setup do
    previous = Application.get_env(:vxpipe_calls, Vxpipe.Calls)
    shell = Mix.shell()
    Mix.shell(Mix.Shell.IO)
    keys = Map.new(["old", "new"], &{&1, :crypto.strong_rand_bytes(32)})
    {:ok, old} = CredentialKeyring.new("old", Map.take(keys, ["old"]))
    {:ok, current} = CredentialKeyring.new("new", keys)

    Application.put_env(:vxpipe_calls, Vxpipe.Calls,
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: old]}
    )

    on_exit(fn ->
      Mix.shell(shell)

      if is_nil(previous),
        do: Application.delete_env(:vxpipe_calls, Vxpipe.Calls),
        else: Application.put_env(:vxpipe_calls, Vxpipe.Calls, previous)
    end)

    {:ok, tenant, _issued} = Administration.bootstrap_tenant("Re-encryption operator", [:admin])

    for name <- ["first", "second"] do
      {:ok, _credential} =
        ProviderCredentials.provision(tenant.key, "google", name, "api_key", %{
          "api_key" => name <> "-private-marker"
        })
    end

    configure(current)
    [tenant: tenant, current: current]
  end

  test "the operator resumes bounded batches and prints only counts and key IDs", data do
    first =
      capture_io(fn ->
        Mix.Tasks.Vxpipe.ProviderCredential.Reencrypt.run(["--batch-size", "1"])
      end)

    assert JSON.decode!(first) == %{
             "processed" => 1,
             "current_key_id" => "new",
             "remaining_by_key" => %{"old" => 1}
           }

    second = capture_io(fn -> Mix.Tasks.Vxpipe.ProviderCredential.Reencrypt.run([]) end)

    assert JSON.decode!(second) == %{
             "processed" => 1,
             "current_key_id" => "new",
             "remaining_by_key" => %{}
           }

    repeated =
      capture_io(fn -> Mix.Tasks.Vxpipe.ProviderCredential.Reencrypt.run(["--batch-size=1"]) end)

    assert JSON.decode!(repeated) == %{
             "processed" => 0,
             "current_key_id" => "new",
             "remaining_by_key" => %{}
           }

    refute first <> second <> repeated =~ "private-marker"
    refute first <> second <> repeated =~ data.tenant.key

    for name <- ["first", "second"] do
      assert {:ok, resolved} = ProviderCredentials.resolve(data.tenant.key, "google", name)
      assert resolved.payload == %{"api_key" => name <> "-private-marker"}
      assert resolved.credential.encryption_key_id == "new"
    end
  end

  test "invalid flags and bounds fail before writes and never echo supplied values", data do
    for arguments <- [
          ["--api-key", "flag-private-marker"],
          ["--batch-size", "size-private-marker"],
          ["bare-private-marker"],
          ["--batch-size", "0"],
          ["--batch-size", "501"],
          ["--batch-size", "-1"]
        ] do
      error =
        assert_raise Mix.Error, fn ->
          Mix.Tasks.Vxpipe.ProviderCredential.Reencrypt.run(arguments)
        end

      refute Exception.message(error) =~ "private-marker"
    end

    assert {:ok, credentials} = ProviderCredentials.list(data.tenant.key)
    assert Enum.all?(credentials, &(&1.encryption_key_id == "old"))
  end

  test "missing keys fail safely and a missing configured store cannot report completion" do
    configure(nil)

    assert_raise Mix.Error, ~r/credential_key_unavailable/, fn ->
      Mix.Tasks.Vxpipe.ProviderCredential.Reencrypt.run([])
    end

    Application.put_env(:vxpipe_calls, Vxpipe.Calls, [])

    assert_raise Mix.Error, ~r/credential storage is not configured/, fn ->
      Mix.Tasks.Vxpipe.ProviderCredential.Reencrypt.run([])
    end
  end

  defp configure(keyring) do
    options = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(options, :provider_credential_repository, {
        ProviderCredentialStore,
        [repo: Repo, keyring: keyring]
      })
    )
  end
end
