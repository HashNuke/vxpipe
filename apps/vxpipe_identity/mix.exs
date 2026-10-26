defmodule Vxpipe.Identity.MixProject do
  use Mix.Project

  def project do
    [
      app: :vxpipe_identity,
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
    [extra_applications: [:crypto, :logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:argon2_elixir, "~> 4.1"}
    ]
  end
end
