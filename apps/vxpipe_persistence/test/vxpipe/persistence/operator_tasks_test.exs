defmodule Vxpipe.Persistence.OperatorTasksTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialStore, DefinitionStore, Repo}

  setup do
    previous_shell = Mix.shell()
    previous_calls_config = Application.get_env(:vxpipe_calls, Vxpipe.Calls)

    Mix.shell(Mix.Shell.Process)

    Application.put_env(:vxpipe_calls, Vxpipe.Calls,
      credential_repository: {CredentialStore, Repo},
      definition_repository: {DefinitionStore, Repo},
      registries: %{
        capability_profiles: %{
          "test-model" => %{
            kind: :model_inference,
            provider: :test,
            options: %{model: "test"}
          }
        },
        host_tools: %{}
      }
    )

    on_exit(fn ->
      Mix.shell(previous_shell)

      if previous_calls_config do
        Application.put_env(:vxpipe_calls, Vxpipe.Calls, previous_calls_config)
      else
        Application.delete_env(:vxpipe_calls, Vxpipe.Calls)
      end
    end)

    :ok
  end

  test "bootstraps, rotates, and revokes keys without exposing stored digests" do
    Mix.Tasks.Vxpipe.Tenant.Bootstrap.run([
      "--name",
      "Operator tenant",
      "--scopes",
      "admin,calls"
    ])

    bootstrap = receive_json!()
    tenant_key = bootstrap["tenant_key"]
    first_secret = bootstrap["api_key"]
    first_key_id = bootstrap["api_key_id"]

    assert byte_size(tenant_key) == 16
    assert String.starts_with?(first_secret, "vxp_")
    refute Map.has_key?(bootstrap, "digest")

    Mix.Tasks.Vxpipe.ApiKey.Issue.run([
      "--tenant",
      tenant_key,
      "--name",
      "replacement",
      "--scopes",
      "calls"
    ])

    replacement = receive_json!()
    assert replacement["api_key_id"] != first_key_id
    assert replacement["api_key"] != first_secret

    Mix.Tasks.Vxpipe.ApiKey.Revoke.run([
      "--tenant",
      tenant_key,
      "--key-id",
      first_key_id
    ])

    assert %{"api_key_id" => ^first_key_id, "revoked" => true} = receive_json!()

    assert {:error, :invalid_api_key} =
             Administration.authenticate(tenant_key, first_secret, :calls)

    assert {:ok, _principal} =
             Administration.authenticate(tenant_key, replacement["api_key"], :calls)
  end

  test "saves, publishes, and reads a definition through trusted commands" do
    {:ok, tenant, _issued} = Administration.bootstrap_tenant("Definitions tenant", [:admin])

    path = Path.join(System.tmp_dir!(), "vxpipe-definition-#{System.unique_integer([:positive])}.json")
    File.write!(path, JSON.encode!(definition_input()))
    on_exit(fn -> File.rm(path) end)

    Mix.Tasks.Vxpipe.Definition.Save.run(["--tenant", tenant.key, "--file", path])
    saved = receive_json!()

    assert saved["revision"] == 1
    assert saved["validation_errors"] == []
    assert [%{"participant_ref" => "caller"}] = saved["routes"]

    Mix.Tasks.Vxpipe.Definition.Publish.run([
      "--tenant",
      tenant.key,
      "--definition-id",
      saved["definition_id"],
      "--revision",
      "1"
    ])

    assert %{"published" => true} = receive_json!()

    Mix.Tasks.Vxpipe.Definition.Show.run([
      "--tenant",
      tenant.key,
      "--definition-id",
      saved["definition_id"],
      "--revision",
      "1"
    ])

    shown = receive_json!()
    assert shown["source"]["name"] == "Operator example"
    assert shown["published"] == true
  end

  defp receive_json! do
    assert_receive {:mix_shell, :info, [message]}
    JSON.decode!(message)
  end

  defp definition_input do
    %{
      schema_version: "20260909.01",
      name: "Operator example",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: "test-model"}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
