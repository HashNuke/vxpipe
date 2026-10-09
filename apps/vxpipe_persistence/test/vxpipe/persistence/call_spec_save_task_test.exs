defmodule Vxpipe.Persistence.CallSpecSaveTaskTest do
  use Vxpipe.Persistence.DataCase, async: false
  alias Vxpipe.Calls
  alias Vxpipe.Persistence.{CallSpecStore, CredentialStore}
  alias Mix.Tasks.Vxpipe.CallSpec.Save

  setup do
    previous = Application.get_env(:vxpipe_calls, Calls)
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    Application.put_env(
      :vxpipe_calls,
      Calls,
      Keyword.merge(previous || [],
        credential_repository: {CredentialStore, Repo},
        call_spec_repository: {CallSpecStore, Repo},
        registries: %{host_tools: %{}}
      )
    )

    on_exit(fn ->
      Mix.shell(shell)

      if previous,
        do: Application.put_env(:vxpipe_calls, Calls, previous),
        else: Application.delete_env(:vxpipe_calls, Calls)
    end)

    {:ok, tenant, _} = Calls.bootstrap_tenant("CLI identity", [:admin])
    %{tenant: tenant}
  end

  @tag :tmp_dir
  test "the ID flag references an existing spec and cannot set the ID of a new one", ctx do
    path = Path.join(ctx.tmp_dir, "source.json")

    source = %{
      "schema_version" => "20261004.01",
      "incoming_call" => %{"caller" => "caller", "handled_by" => "assistant"},
      "participants" => %{
        "caller" => %{
          "type" => "human",
          "connection" => %{"service" => "web", "mode" => "receive", "admission" => "start_call"}
        },
        "assistant" => %{"type" => "agent", "prompt" => "Help."}
      }
    }

    File.write!(path, JSON.encode!(source))
    args = ["--tenant", ctx.tenant.key, "--file", path]
    assert_raise Mix.Error, ~r/not_found/, fn -> Save.run(args ++ ["--call-spec-id", "new"]) end
    assert {:error, :not_found} = Calls.fetch_call_spec(ctx.tenant.key, "new", 1)
    Save.run(args)
    assert_receive {:mix_shell, :info, [json]}
    first = JSON.decode!(json)
    id = first["call_spec_id"]
    assert id =~ ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
    Save.run(args ++ ["--call-spec-id", id])
    assert_receive {:mix_shell, :info, [updated]}
    assert JSON.decode!(updated)["call_spec_id"] == id
    assert JSON.decode!(updated)["revision"] == 2
  end
end
