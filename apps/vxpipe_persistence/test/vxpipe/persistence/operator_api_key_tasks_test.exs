defmodule Vxpipe.Persistence.OperatorApiKeyTasksTest do
  use Vxpipe.Persistence.DataCase, async: false
  import Bitwise
  import Ecto.Query
  alias Vxpipe.Calls

  setup do
    previous = Application.get_env(:vxpipe_calls, Calls)
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    Application.put_env(:vxpipe_calls, Calls,
      operator_api_key_repository: {Vxpipe.Persistence.OperatorApiKeyStore, Repo}
    )

    on_exit(fn ->
      Mix.shell(shell)

      if previous,
        do: Application.put_env(:vxpipe_calls, Calls, previous),
        else: Application.delete_env(:vxpipe_calls, Calls)
    end)
  end

  @tag :tmp_dir
  test "a failed output writer revokes the issued key and removes the incomplete file", %{
    tmp_dir: dir
  } do
    file = Path.join(dir, "failed.json")

    assert {:error, :operator_key_output_failed} =
             Vxpipe.Persistence.OperatorKeyFile.issue(:bootstrap, file,
               write: fn _device, _contents -> raise "private output failure" end
             )

    refute File.exists?(file)

    assert Repo.aggregate(
             from(k in Vxpipe.Persistence.Schema.OperatorApiKey, where: is_nil(k.revoked_at)),
             :count
           ) == 0

    assert {:error, :operator_key_already_initialized} = Calls.bootstrap_operator_api_key()
  end

  @tag :tmp_dir
  test "writes each issued secret once to a new private file and keeps terminal output safe", %{
    tmp_dir: dir
  } do
    first_file = Path.join(dir, "first.json")
    Mix.Tasks.Vxpipe.OperatorKey.Bootstrap.run(["--output", first_file])
    first = JSON.decode!(File.read!(first_file))
    assert band(File.stat!(first_file).mode, 0o777) == 0o600
    assert {:ok, _} = Calls.authenticate_operator(first["api_key"])
    assert_received {:mix_shell, :info, [message]}
    refute message =~ first["api_key"]
    refute message =~ "digest"

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Vxpipe.OperatorKey.Replace.run(["--output", first_file])
    end

    assert {:ok, _} = Calls.authenticate_operator(first["api_key"])
    assert JSON.decode!(File.read!(first_file)) == first

    retry_file = Path.join(dir, "retry.json")

    assert_raise Mix.Error, fn ->
      Mix.Tasks.Vxpipe.OperatorKey.Bootstrap.run(["--output", retry_file])
    end

    refute File.exists?(retry_file)

    next_file = Path.join(dir, "replacement.json")
    Mix.Tasks.Vxpipe.OperatorKey.Replace.run(["--output", next_file])
    replacement = JSON.decode!(File.read!(next_file))
    assert {:error, :invalid_api_key} = Calls.authenticate_operator(first["api_key"])
    assert {:ok, _} = Calls.authenticate_operator(replacement["api_key"])
    Mix.Tasks.Vxpipe.OperatorKey.Revoke.run(["--key-id", replacement["api_key_id"]])
    assert {:error, :invalid_api_key} = Calls.authenticate_operator(replacement["api_key"])
  end
end
