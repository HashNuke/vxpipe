defmodule Vxpipe.Persistence.ProviderCredentialTasksTest do
  use Vxpipe.Persistence.DataCase, async: false

  import ExUnit.CaptureIO

  alias Vxpipe.Calls.{Administration, ProviderCredentials}
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, ProviderCredentialStore, Repo}

  setup do
    previous = Application.get_env(:vxpipe_calls, Vxpipe.Calls)
    shell = Mix.shell()
    Mix.shell(Mix.Shell.IO)
    {:ok, ring} = CredentialKeyring.new("v1", %{"v1" => :crypto.strong_rand_bytes(32)})

    Application.put_env(:vxpipe_calls, Vxpipe.Calls,
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: ring]}
    )

    on_exit(fn ->
      Mix.shell(shell)
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, previous)
    end)

    {:ok, tenant, _issued} = Administration.bootstrap_tenant("Provisioning operator", [:admin])
    [tenant: tenant]
  end

  test "trusted operator provisions from stdin and lists metadata without echoing credentials", %{
    tenant: tenant
  } do
    output =
      capture_io(~s({"api_key":"operator-secret"}), fn ->
        Mix.Tasks.Vxpipe.ProviderCredential.Provision.run([
          "--tenant",
          tenant.key,
          "--provider",
          "google"
        ])
      end)

    summary = JSON.decode!(output)
    assert summary["provider"] == "google"
    assert summary["name"] == "default"
    assert summary["version"] == 1
    assert summary["status"] == "active"
    refute output =~ "operator-secret"

    listed =
      capture_io(fn -> Mix.Tasks.Vxpipe.ProviderCredential.List.run(["--tenant", tenant.key]) end)

    assert JSON.decode!(listed) == [summary]
    refute listed =~ "operator-secret"
    assert {:ok, resolved} = ProviderCredentials.resolve(tenant.key, "google")
    assert resolved.payload == %{"api_key" => "operator-secret"}
  end

  test "invalid secret input and secret flags never appear in diagnostics", %{tenant: tenant} do
    for input <- [
          "sensitive-not-json",
          ~s({"api_key":"secret","auth_file":"secret-path"}),
          String.duplicate("x", 16_385)
        ] do
      capture_io(input, fn ->
        error =
          assert_raise Mix.Error, fn ->
            Mix.Tasks.Vxpipe.ProviderCredential.Provision.run([
              "--tenant",
              tenant.key,
              "--provider",
              "google"
            ])
          end

        refute Exception.message(error) =~ input
        refute Exception.message(error) =~ "secret-path"
      end)
    end

    error =
      assert_raise Mix.Error, fn ->
        Mix.Tasks.Vxpipe.ProviderCredential.Provision.run([
          "--tenant",
          tenant.key,
          "--provider",
          "google",
          "--api-key",
          "flag-secret"
        ])
      end

    refute Exception.message(error) =~ "flag-secret"
    assert {:ok, []} = ProviderCredentials.list(tenant.key)
  end

  test "trusted operator provisions a named Telnyx key through protected input", %{tenant: tenant} do
    output =
      capture_io(~s({"api_key":"telnyx-operator-private-marker"}), fn ->
        Mix.Tasks.Vxpipe.ProviderCredential.Provision.run([
          "--tenant",
          tenant.key,
          "--provider",
          "telnyx",
          "--name",
          "support-phone"
        ])
      end)

    summary = JSON.decode!(output)
    assert summary["tenant_key"] == tenant.key
    assert summary["provider"] == "telnyx"
    assert summary["name"] == "support-phone"
    assert summary["auth_kind"] == "api_key"
    assert summary["status"] == "active"
    refute output =~ "private-marker"

    listed =
      capture_io(fn -> Mix.Tasks.Vxpipe.ProviderCredential.List.run(["--tenant", tenant.key]) end)

    assert JSON.decode!(listed) == [summary]
    refute listed =~ "private-marker"

    assert {:ok, resolved} = ProviderCredentials.resolve(tenant.key, "telnyx", "support-phone")
    assert resolved.payload == %{"api_key" => "telnyx-operator-private-marker"}
  end

  test "terminal stdin is rejected before the credential payload is read" do
    terminal = start_supervised!({Vxpipe.Persistence.Test.ProviderCredentialInput, owner: self()})
    previous = Process.group_leader()

    try do
      Process.group_leader(self(), terminal)

      assert_raise Mix.Error, ~r/protected stdin/, fn ->
        Vxpipe.Persistence.ProviderCredentialCLI.payload!()
      end
    after
      Process.group_leader(self(), previous)
    end

    refute_received :credential_input_read
  end

  test "trusted operator provisions existing Twilio auth without echoing its payload", %{
    tenant: tenant
  } do
    payload = %{
      "account_sid" => "AC00000000000000000000000000000000",
      "auth_token" => "twilio-operator-private-marker"
    }

    output =
      capture_io(JSON.encode!(payload), fn ->
        Mix.Tasks.Vxpipe.ProviderCredential.Provision.run([
          "--tenant",
          tenant.key,
          "--provider",
          "twilio",
          "--name",
          "phone",
          "--auth-kind",
          "account_sid_auth_token"
        ])
      end)

    summary = JSON.decode!(output)
    assert summary["provider"] == "twilio"
    assert summary["auth_kind"] == "account_sid_auth_token"
    refute output =~ payload["auth_token"]
    refute output =~ payload["account_sid"]
    assert {:ok, snapshot} = ProviderCredentials.resolve(tenant.key, "twilio", "phone")
    assert snapshot.payload == payload
  end

  test "provision and list accept generated tenant keys that begin with a dash", %{tenant: tenant} do
    tenant_key = "-AAAAAAAAAAAAAAA"

    Repo.get_by!(Vxpipe.Persistence.Schema.Tenant, key: tenant.key)
    |> Ecto.Changeset.change(key: tenant_key)
    |> Repo.update!()

    provisioned =
      capture_io(~s({"api_key":"dash-tenant-secret"}), fn ->
        Mix.Tasks.Vxpipe.ProviderCredential.Provision.run([
          "--tenant",
          tenant_key,
          "--provider",
          "google"
        ])
      end)

    listed =
      capture_io(fn -> Mix.Tasks.Vxpipe.ProviderCredential.List.run(["--tenant", tenant_key]) end)

    assert JSON.decode!(listed) == [JSON.decode!(provisioned)]
    refute listed =~ "dash-tenant-secret"
  end
end
