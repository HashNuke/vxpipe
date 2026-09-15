defmodule Vxpipe.Persistence.TelephonyServiceTaskTest do
  use Vxpipe.Persistence.DataCase, async: false

  import ExUnit.CaptureIO

  alias Vxpipe.Calls.{Administration, ProviderCredentials, TelephonyServices}
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, ProviderCredentialStore, Repo}
  alias Vxpipe.Persistence.TelephonyServiceStore

  @moduletag :tmp_dir

  setup %{tmp_dir: temp_dir} do
    previous = Application.get_env(:vxpipe_calls, Vxpipe.Calls)
    shell = Mix.shell()
    Mix.shell(Mix.Shell.IO)
    {:ok, keyring} = CredentialKeyring.new("v1", %{"v1" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    Application.put_env(:vxpipe_calls, Vxpipe.Calls,
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context}
    )

    on_exit(fn ->
      File.rm_rf!(temp_dir)
      Mix.shell(shell)
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, previous)
    end)

    {:ok, tenant, _issued} = Administration.bootstrap_tenant("Service operator", [:admin])

    {:ok, credential} =
      ProviderCredentials.provision(tenant.key, "telnyx", "phone-key", "api_key", %{
        "api_key" => "operator-private-key-marker"
      })

    [tenant: tenant, credential: credential]
  end

  test "operator registers metadata against a provisioned key and receives public IDs", data do
    path = Path.join(data.tmp_dir, "telnyx-service.json")
    File.write!(path, JSON.encode!(attributes(data.credential.id)))

    output =
      capture_io(fn ->
        Mix.Tasks.Vxpipe.TelephonyService.Register.run([
          "--tenant",
          data.tenant.key,
          "--file",
          path
        ])
      end)

    summary = JSON.decode!(output)
    assert summary["tenant_key"] == data.tenant.key
    assert summary["provider"] == "telnyx"
    assert summary["name"] == "support-phone"
    assert summary["ingress_key"] == "support-ingress"
    assert summary["credential_id"] == data.credential.id
    refute output =~ "operator-private-key-marker"
    refute output =~ "encrypted_payload"

    assert {:ok, service} = TelephonyServices.fetch(data.tenant.key, "support-phone")
    assert summary["service_id"] == service.id
    assert service.answering_machine_detection == :disabled
    assert {:ok, ^service} = TelephonyServices.fetch_by_ingress("support-ingress")
  end

  test "malformed, secret-bearing and oversized files fail without echoing input", data do
    path = Path.join(data.tmp_dir, "invalid-service.json")

    for input <- [
          "private-invalid-content",
          JSON.encode!(
            Map.put(attributes(data.credential.id), "api_key", "private-input-marker")
          ),
          String.duplicate("x", 16_385)
        ] do
      File.write!(path, input)

      output =
        capture_io(fn ->
          error =
            assert_raise Mix.Error, fn ->
              Mix.Tasks.Vxpipe.TelephonyService.Register.run([
                "--tenant",
                data.tenant.key,
                "--file",
                path
              ])
            end

          refute Exception.message(error) =~ "private-input-marker"
          refute Exception.message(error) =~ input
        end)

      assert output == ""
    end

    assert {:error, :telephony_service_not_found} =
             TelephonyServices.fetch(data.tenant.key, "support-phone")
  end

  test "secret command-line flags are rejected without printing their values", data do
    error =
      assert_raise Mix.Error, fn ->
        Mix.Tasks.Vxpipe.TelephonyService.Register.run([
          "--tenant",
          data.tenant.key,
          "--api-key",
          "private-flag-marker"
        ])
      end

    refute Exception.message(error) =~ "private-flag-marker"
  end

  defp attributes(credential_id) do
    %{
      "provider" => "telnyx",
      "name" => "support-phone",
      "ingress_key" => "support-ingress",
      "provider_connection_id" => "connection-1",
      "credential_id" => credential_id,
      "public_key" => Base.encode64(:binary.copy(<<1>>, 32))
    }
  end
end
