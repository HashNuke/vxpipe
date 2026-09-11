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
      mod: {Vxpipe.Gateway.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.12"},
      {:cors_plug, "~> 3.0"},
      {:ex_sctp, "~> 0.1.3"},
      {:ex_webrtc, "~> 0.17.0"},
      {:membrane_opus_plugin, "~> 0.21.0"},
      {:membrane_raw_audio_parser_plugin, "~> 0.5.0"},
      {:membrane_rtp_opus_plugin, "~> 0.10.3"},
      {:membrane_rtp_plugin, "~> 0.31.5"},
      {:numbers, "== 5.2.4", override: true},
      {:plug, "~> 1.20"},
      {:telemetry, "~> 1.3"},
      {:vxpipe_call_engine, in_umbrella: true},
      {:vxpipe_calls, in_umbrella: true}
    ]
  end
end
