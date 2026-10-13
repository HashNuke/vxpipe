defmodule Vxpipe.Console.OperatorLoginTaskTest do
  @moduledoc """
  `mix vxpipe.login` no longer issues operator login challenges.

  It issues a local one-time setup proof for upgraded installations via the
  configured `:user_identity_backend`. Legacy challenge repositories are never
  consulted. See `SetupProofTaskTest` for the primary pending-proof case.
  """

  use ExUnit.Case, async: false

  defmodule PendingProofBackend do
    def status, do: {:ok, :pending_operator_proof}
    def issue_setup_proof, do: {:ok, %{proof: String.duplicate("p", 43)}}
  end

  defmodule FirstRunBackend do
    def status, do: {:ok, :pending_first_run}
    def issue_setup_proof, do: {:error, :unexpected}
  end

  defmodule CompleteBackend do
    def status, do: {:ok, :complete}
    def issue_setup_proof, do: {:error, :unexpected}
  end

  defmodule UnavailableBackend do
    def status, do: {:ok, :pending_operator_proof}
    def issue_setup_proof, do: {:error, :database_unavailable}
  end

  setup do
    previous_shell = Mix.shell()
    previous_backend = Application.get_env(:vxpipe_console, :user_identity_backend)
    previous_calls = Application.get_env(:vxpipe_calls, Vxpipe.Calls)

    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(previous_shell)

      if previous_backend,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, previous_backend),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)

      restore(:vxpipe_calls, Vxpipe.Calls, previous_calls)
      Mix.Task.reenable("vxpipe.login")
    end)

    :ok
  end

  test "issues only a local setup proof and never an operator challenge URL" do
    Application.put_env(:vxpipe_console, :user_identity_backend, PendingProofBackend)
    configure_legacy_challenge_repository(self())

    Mix.Tasks.Vxpipe.Login.run([])

    assert_receive {:mix_shell, :info, ["Setup proof: " <> proof]}
    assert proof == String.duplicate("p", 43)

    assert_receive {:mix_shell, :info, ["Open /auth/setup and enter the proof" <> _]}
    refute_receive {:mix_shell, :info, ["Operator login URL: " <> _]}
    refute_receive {:mix_shell, :info, ["Operator login code: " <> _]}
    refute_received {:operator_login_challenge_inserted, _}
  end

  test "fresh installations set up without a local proof" do
    Application.put_env(:vxpipe_console, :user_identity_backend, FirstRunBackend)

    error = assert_raise Mix.Error, fn -> Mix.Tasks.Vxpipe.Login.run([]) end
    assert Exception.message(error) =~ "without a local proof"
    refute_received {:mix_shell, :info, _}
  end

  test "completed installations do not issue another proof" do
    Application.put_env(:vxpipe_console, :user_identity_backend, CompleteBackend)

    error = assert_raise Mix.Error, fn -> Mix.Tasks.Vxpipe.Login.run([]) end
    assert Exception.message(error) =~ "already set up"
    refute_received {:mix_shell, :info, _}
  end

  test "persistence failure prints no proof" do
    Application.put_env(:vxpipe_console, :user_identity_backend, UnavailableBackend)

    error = assert_raise Mix.Error, fn -> Mix.Tasks.Vxpipe.Login.run([]) end
    assert Exception.message(error) =~ "check database configuration"
    refute_received {:mix_shell, :info, _}
  end

  defp configure_legacy_challenge_repository(observer) do
    Application.put_env(:vxpipe_calls, Vxpipe.Calls,
      operator_login_challenge_repository:
        {Vxpipe.Console.Test.OperatorLoginChallengeRepository, {observer, :ok}}
    )
  end

  defp restore(application, key, nil), do: Application.delete_env(application, key)
  defp restore(application, key, value), do: Application.put_env(application, key, value)
end
