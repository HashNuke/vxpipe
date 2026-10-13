defmodule Vxpipe.Console.SetupProofTaskTest do
  use ExUnit.Case, async: false

  defmodule Backend do
    def status, do: {:ok, :pending_operator_proof}
    def issue_setup_proof, do: {:ok, %{proof: String.duplicate("p", 43)}}
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

  test "the local task issues only a one-time setup proof for an upgraded installation" do
    Mix.Tasks.Vxpipe.Login.run([])

    assert_receive {:mix_shell, :info, ["Setup proof: " <> proof]}
    assert proof == String.duplicate("p", 43)

    assert_receive {:mix_shell, :info,
                    ["Open /auth/setup and enter the proof with the new Superadmin credentials."]}

    refute_receive {:mix_shell, :info, ["Operator login URL: " <> _]}
  end
end
