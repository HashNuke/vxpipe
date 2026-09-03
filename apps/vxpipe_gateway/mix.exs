defmodule Vxpipe.Gateway.MixProject do
  use Mix.Project

  def project do
    [
      app: :vxpipe_gateway,
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
      mod: {Vxpipe.Gateway.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.12"},
      {:cors_plug, "~> 3.0"},
      {:plug, "~> 1.20"},
      {:vxpipe_call_engine, in_umbrella: true}
    ]
  end
end
