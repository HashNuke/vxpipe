defmodule Vxpipe.Console.MixProject do
  use Mix.Project

  def project do
    [
      app: :vxpipe_console,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Vxpipe.Console.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.12"},
      {:lazy_html, "~> 0.1", only: :test},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_dashboard, "~> 0.9.1"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:telemetry, "~> 1.3"},
      {:vxpipe_gateway, in_umbrella: true}
    ]
  end
end
