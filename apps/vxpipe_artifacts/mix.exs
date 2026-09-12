defmodule Vxpipe.Artifacts.MixProject do
  use Mix.Project

  def project do
    [
      app: :vxpipe_artifacts,
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
      extra_applications: [:crypto, :logger],
      mod: {Vxpipe.Artifacts.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:ex_aws, "~> 2.7"},
      {:ex_aws_s3, "~> 2.5"},
      {:req, "~> 0.7.4"},
      {:sweet_xml, "~> 0.7.5"},
      {:vxpipe_call_engine, in_umbrella: true, runtime: false},
      {:vxpipe_calls, in_umbrella: true, runtime: false}
    ]
  end
end
