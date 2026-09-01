defmodule Vxpipe.Server.MixProject do
  use Mix.Project

  def project do
    [
      app: :vxpipe_server,
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

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Vxpipe.Server.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:vxpipe, in_umbrella: true},
      {:vxpipe_web, in_umbrella: true},
      {:bandit, "~> 1.12"}
    ]
  end
end
