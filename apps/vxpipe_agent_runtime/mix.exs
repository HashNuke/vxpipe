defmodule Vxpipe.AgentRuntime.MixProject do
  use Mix.Project

  def project do
    [
      app: :vxpipe_agent_runtime,
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

  def application do
    [
      extra_applications: [:logger],
      mod: {Vxpipe.AgentRuntime.Application, []}
    ]
  end

  defp deps do
    [
      {:jsv, "~> 0.22"},
      {:plug, "~> 1.20", only: :test},
      {:req_llm, "~> 1.22"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]
end
