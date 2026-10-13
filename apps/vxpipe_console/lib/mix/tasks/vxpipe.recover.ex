defmodule Mix.Tasks.Vxpipe.Recover do
  use Mix.Task

  @shortdoc "Issues a local one-time Superadmin recovery proof"
  @requirements ["app.config"]

  @impl true
  def run([]) do
    ensure_persistence_started!()

    with {:ok, :complete} <- backend().status(),
         {:ok, %{proof: proof}} <- backend().issue_recovery_proof() do
      Mix.shell().info("Recovery proof: #{proof}")

      Mix.shell().info(
        "Open /auth/recover and enter the proof with a Superadmin email and new password."
      )
    else
      {:ok, _pending} ->
        Mix.raise("Console authentication must be set up before recovery")

      {:error, _reason} ->
        Mix.raise("could not issue a recovery proof; check database configuration")
    end
  end

  def run(_arguments), do: Mix.raise("vxpipe.recover does not accept arguments")

  defp ensure_persistence_started! do
    case Application.ensure_all_started(:vxpipe_persistence) do
      {:ok, _applications} -> :ok
      {:error, _reason} -> Mix.raise("could not start configured Vxpipe persistence")
    end
  end

  defp backend,
    do: Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)
end
