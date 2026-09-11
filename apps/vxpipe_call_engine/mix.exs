defmodule Vxpipe.CallEngine.MixProject do
  use Mix.Project

  def project do
    [
      app: :vxpipe_call_engine,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:crypto, :logger],
      mod: {Vxpipe.CallEngine.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.12", only: :test},
      {:decimal, "~> 2.0"},
      {:jsv, "~> 0.22"},
      {:membrane_audio_mix_plugin, "~> 0.16.5"},
      {:req, "~> 0.7.4"},
      {:req_llm, "~> 1.22"},
      {:telemetry, "~> 1.3"},
      {:vxpipe_agent_runtime, in_umbrella: true},
      {:vxpipe_mcp, in_umbrella: true},
      {:websockex, "~> 0.5.1"}
    ]
  end
end
