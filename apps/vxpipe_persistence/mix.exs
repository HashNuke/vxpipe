defmodule Vxpipe.Persistence.MixProject do
  use Mix.Project

  def project do
    [
      app: :vxpipe_persistence,
      version: File.read!(Path.expand("../../VERSION", __DIR__)) |> String.trim(),
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
      extra_applications: [:crypto, :logger],
      mod: {Vxpipe.Persistence.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:boruta, "== 2.3.8"},
      {:ecto_sql, "~> 3.13.5"},
      {:plug, "~> 1.20"},
      {:postgrex, "~> 0.21.1"},
      {:vxpipe_artifacts, in_umbrella: true, runtime: false},
      {:vxpipe_calls, in_umbrella: true},
      {:vxpipe_identity, in_umbrella: true}
    ]
  end
end
