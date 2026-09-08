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
      {:phoenix, "~> 1.8"},
      {:vxpipe_gateway, in_umbrella: true}
    ]
  end
end
