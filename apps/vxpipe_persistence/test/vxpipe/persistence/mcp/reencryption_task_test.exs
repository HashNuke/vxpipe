defmodule Vxpipe.Persistence.MCP.ReencryptionTaskTest do
  use Vxpipe.Persistence.DataCase, async: false
  import ExUnit.CaptureIO

  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore}
  alias Vxpipe.Persistence.MCP.ConnectionStore

  setup do
    previous = Application.get_env(:vxpipe_calls, Vxpipe.Calls)
    shell = Mix.shell()
    Mix.shell(Mix.Shell.IO)

    on_exit(fn ->
      Mix.shell(shell)

      if previous,
        do: Application.put_env(:vxpipe_calls, Vxpipe.Calls, previous),
        else: Application.delete_env(:vxpipe_calls, Vxpipe.Calls)
    end)

    keys = Map.new(["old", "new"], &{&1, :crypto.strong_rand_bytes(32)})
    {:ok, old} = CredentialKeyring.new("old", keys)
    {:ok, current} = CredentialKeyring.new("new", keys)

    {:ok, tenant, _} =
      Administration.bootstrap_tenant("MCP rotation", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    records =
      for method <- ["bearer", "oauth"] do
        attributes = %{
          endpoint: "https://#{method}.example.test/mcp",
          endpoint_identity: "https://#{method}.example.test/mcp",
          server_name: method,
          auth_method: method,
          catalog: []
        }

        secrets =
          if method == "bearer",
            do: %{"token" => "private-marker"},
            else: %{
              "access_token" => "private-marker",
              "refresh_token" => "private-refresh",
              "grant_revision" => 7
            }

        {:ok, record} =
          ConnectionStore.create([repo: Repo, keyring: old], tenant.key, attributes, secrets)

        {record, secrets}
      end

    context = [repo: Repo, keyring: current]

    Application.put_env(:vxpipe_calls, Vxpipe.Calls,
      mcp_connection_repository: {ConnectionStore, context}
    )

    %{tenant: tenant.key, records: records, context: context}
  end

  test "resumable batches rotate static credentials and OAuth grants without changing identity",
       data do
    first =
      capture_io(fn -> Mix.Tasks.Vxpipe.McpCredential.Reencrypt.run(["--batch-size", "1"]) end)

    assert JSON.decode!(first) == %{
             "processed" => 1,
             "current_key_id" => "new",
             "remaining_by_key" => %{"old" => 1}
           }

    second = capture_io(fn -> Mix.Tasks.Vxpipe.McpCredential.Reencrypt.run([]) end)

    assert JSON.decode!(second) == %{
             "processed" => 1,
             "current_key_id" => "new",
             "remaining_by_key" => %{}
           }

    refute first <> second =~ "private"
    refute first <> second =~ data.tenant

    for {record, secrets} <- data.records do
      assert {:ok, saved} = ConnectionStore.resolve(data.context, data.tenant, record.id)
      assert saved.connection == record
      assert saved.secrets == secrets
    end
  end

  test "rejects invalid flags without echoing values" do
    for arguments <- [
          ["--token", "private-marker"],
          ["--batch-size", "0"],
          ["--batch-size", "501"],
          ["private-marker"]
        ] do
      error =
        assert_raise Mix.Error, fn -> Mix.Tasks.Vxpipe.McpCredential.Reencrypt.run(arguments) end

      refute Exception.message(error) =~ "private-marker"
    end
  end

  test "missing keyring and missing storage cannot report success", data do
    Application.put_env(:vxpipe_calls, Vxpipe.Calls,
      mcp_connection_repository: {ConnectionStore, Keyword.put(data.context, :keyring, nil)}
    )

    assert_raise Mix.Error, ~r/credential_key_unavailable/, fn ->
      Mix.Tasks.Vxpipe.McpCredential.Reencrypt.run([])
    end

    Application.put_env(:vxpipe_calls, Vxpipe.Calls, [])

    assert_raise Mix.Error, ~r/MCP credential storage is not configured/, fn ->
      Mix.Tasks.Vxpipe.McpCredential.Reencrypt.run([])
    end
  end
end
