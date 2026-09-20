defmodule Vxpipe.Gateway.BundlexProject do
  use Bundlex.Project

  def project do
    [natives: natives(Bundlex.get_target())]
  end

  defp natives(_platform) do
    [
      speech_opus_decoder: [
        sources: ["speech_opus_decoder.c"],
        os_deps: [
          opus: [
            {:precompiled,
             Membrane.PrecompiledDependencyProvider.get_dependency_url(:opus,
               version: "1.5.2"
             )},
            :pkg_config
          ]
        ],
        interface: :nif,
        preprocessor: Unifex
      ]
    ]
  end
end
