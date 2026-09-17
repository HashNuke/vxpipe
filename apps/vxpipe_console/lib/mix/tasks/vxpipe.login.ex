defmodule Mix.Tasks.Vxpipe.Login do
  use Mix.Task

  alias Vxpipe.Console.OperatorLoginConfiguration

  @shortdoc "Issues a short-lived installation-operator login challenge"
  @requirements ["app.config"]

  @impl true
  def run([]) do
    configuration = configuration!()
    ensure_persistence_started!()

    case Vxpipe.Calls.issue_operator_login_challenge(configuration.verifier_secret) do
      {:ok, issued} ->
        Mix.shell().info("Operator login URL: #{login_url(configuration.origin, issued.token)}")
        Mix.shell().info("Operator login code: #{issued.code}")

      {:error, _reason} ->
        Mix.raise("could not persist an operator login challenge; check database configuration")
    end
  end

  def run(_arguments), do: Mix.raise("vxpipe.login does not accept arguments")

  defp ensure_persistence_started! do
    case Application.ensure_all_started(:vxpipe_persistence) do
      {:ok, _applications} -> :ok
      {:error, _reason} -> Mix.raise("could not start configured Vxpipe persistence")
    end
  end

  defp configuration! do
    case OperatorLoginConfiguration.load() do
      {:ok, configuration} ->
        configuration

      {:error, :invalid_operator_login_origin} ->
        Mix.raise("configure an explicit HTTPS endpoint URL, or HTTP on a loopback host")

      {:error, :invalid_operator_login_secret} ->
        Mix.raise("configure SECRET_KEY_BASE with at least 64 bytes")
    end
  end

  defp login_url(origin, token), do: origin <> "/auth/login-token/" <> token
end
