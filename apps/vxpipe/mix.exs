defmodule Vxpipe.MixProject do
  use Mix.Project

  def project do
    [
      app: :vxpipe,
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
      mod: {Vxpipe.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:membrane_audio_mix_plugin, "~> 0.16"},
      {:membrane_core, "~> 1.3"},
      {:membrane_raw_audio_format, "~> 0.12"}
    ]
  end
end
