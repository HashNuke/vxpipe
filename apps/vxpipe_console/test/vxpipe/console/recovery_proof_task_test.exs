defmodule Vxpipe.Console.RecoveryProofTaskTest do
  use ExUnit.Case, async: false

  defmodule Backend do
    def status, do: {:ok, :complete}
    def issue_recovery_proof, do: {:ok, %{proof: String.duplicate("r", 43)}}
  end

  setup do
    original_backend = Application.get_env(:vxpipe_console, :user_identity_backend)
    original_shell = Mix.shell()
    Application.put_env(:vxpipe_console, :user_identity_backend, Backend)
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      if original_backend,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, original_backend),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)

      Mix.shell(original_shell)
    end)

    :ok
  end

  test "the local task issues one-time recovery proof after setup" do
    Mix.Tasks.Vxpipe.Recover.run([])

    assert_receive {:mix_shell, :info, ["Recovery proof: " <> proof]}
    assert proof == String.duplicate("r", 43)

    assert_receive {:mix_shell, :info,
                    [
                      "Open /auth/recover and enter the proof with a Superadmin email and new password."
                    ]}
  end
end
