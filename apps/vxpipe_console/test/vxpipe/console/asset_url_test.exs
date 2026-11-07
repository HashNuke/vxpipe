defmodule Vxpipe.Console.AssetURLTest do
  use ExUnit.Case, async: true

  @tag :tmp_dir
  test "bundled service logos resolve to static assets from nested tenant pages", %{tmp_dir: tmp} do
    profile = Esbuild.config_for!(:vxpipe_console)
    assets = Keyword.fetch!(profile, :cd)
    source = Path.join(assets, "src/admin/assets/icons/cartesia.svg")
    entry = Path.join(tmp, "asset_url_probe.js")
    output = Path.join(tmp, "output")
    File.write!(entry, "import logo from #{JSON.encode!(source)}; console.log(logo);\n")

    arguments =
      profile
      |> Keyword.fetch!(:args)
      |> Enum.filter(&String.starts_with?(&1, "--"))
      |> Kernel.++([entry, "--outdir=#{output}", "--log-level=error"])

    assert {_build_output, 0} =
             System.cmd(Esbuild.bin_path(), arguments,
               cd: assets,
               env: profile |> Keyword.fetch!(:env) |> Enum.to_list(),
               stderr_to_stdout: true
             )

    assert {exported_url, 0} =
             System.cmd("node", [Path.join(output, "asset_url_probe.js")], stderr_to_stdout: true)

    exported_url = String.trim(exported_url)
    filename = Path.basename(exported_url)
    assert File.read!(Path.join(output, filename)) == File.read!(source)

    assert URI.merge("https://console.example.test/t/tenant/services/ai", exported_url).path ==
             "/assets/" <> filename
  end
end
