defmodule Vxpipe.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": [
        "do --app vxpipe_console cmd --cd ../.. npm ci",
        "do --app vxpipe_console cmd --cd ../.. npm run build",
        "do --app vxpipe_console cmd --cd assets npm ci",
        "do --app vxpipe_console esbuild.install --if-missing"
      ],
      "assets.build": [
        "do --app vxpipe_console cmd --cd assets npm run check",
        "do --app vxpipe_console cmd --cd assets npm run css:build",
        "do --app vxpipe_console esbuild vxpipe_console"
      ],
      "assets.deploy": [
        "do --app vxpipe_console cmd --cd assets npm run check",
        "do --app vxpipe_console cmd --cd assets npm run css:build -- --minify",
        "do --app vxpipe_console esbuild vxpipe_console --minify"
      ],
      "assets.test": ["do --app vxpipe_console cmd --cd assets npm test"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "deps.unlock --check-unused"
      ]
    ]
  end
end
