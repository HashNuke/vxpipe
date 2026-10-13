defmodule Mix.Tasks.Vxpipe.Login do
  use Mix.Task

  @shortdoc "Issues a local one-time proof for upgraded Console setup"
  @requirements ["app.config"]

  @impl true
  def run([]) do
    ensure_persistence_started!()

    with {:ok, :pending_operator_proof} <- backend().status(),
         {:ok, %{proof: proof}} <- backend().issue_setup_proof() do
      Mix.shell().info("Setup proof: #{proof}")

      Mix.shell().info(
        "Open /auth/setup and enter the proof with the new Superadmin credentials."
      )
    else
      {:ok, :pending_first_run} ->
        Mix.raise("fresh installations can set up at /auth/setup without a local proof")

      {:ok, :complete} ->
        Mix.raise("Console authentication is already set up")

      {:error, _reason} ->
        Mix.raise("could not issue a setup proof; check database configuration")
    end
  end

  def run(_arguments), do: Mix.raise("vxpipe.login does not accept arguments")

  defp ensure_persistence_started! do
    case Application.ensure_all_started(:vxpipe_persistence) do
      {:ok, _applications} -> :ok
      {:error, _reason} -> Mix.raise("could not start configured Vxpipe persistence")
    end
  end

  defp backend,
    do: Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)
end
