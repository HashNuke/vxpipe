defmodule Vxpipe.MCP.MixProject do
  use Mix.Project

  def project do
    [
      app: :vxpipe_mcp,
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
      mod: {Vxpipe.MCP.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_mcp, "== 1.3.0"},
      {:jason, "~> 1.4"},
      {:jsv, "~> 0.22"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]
end
