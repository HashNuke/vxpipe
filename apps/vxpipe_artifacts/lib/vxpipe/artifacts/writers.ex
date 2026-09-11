defmodule Vxpipe.Artifacts.Writers do
  @moduledoc "Starts call-scoped artifact writers through their owning supervisor."

  alias Vxpipe.Artifacts.{ArtifactSpec, Writer}

  @supervisor Vxpipe.Artifacts.WriterSupervisor

  @spec start_writer(keyword()) :: DynamicSupervisor.on_start_child()
  def start_writer(options) when is_list(options) do
    with {:ok, value} <- Keyword.fetch(options, :spec),
         {:ok, spec} <- ArtifactSpec.new(value) do
      options = Keyword.put(options, :spec, spec)
      DynamicSupervisor.start_child(@supervisor, {Writer, options})
    else
      :error -> {:error, :invalid_artifact_spec}
      {:error, _reason} = error -> error
    end
  end
end
