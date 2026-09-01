defmodule Vxpipe.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      default_release: :vxpipe,
      releases: releases(),
      deps: deps()
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    []
  end

  defp releases do
    [
      vxpipe: [
        version: {:from_app, :vxpipe_server},
        applications: [vxpipe_server: :permanent]
      ]
    ]
  end
end
