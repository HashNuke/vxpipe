defmodule Vxpipe.Artifacts.Metadata.Publishers do
  @moduledoc false

  alias Vxpipe.Artifacts.Metadata.{Configuration, Publisher}
  alias Vxpipe.Artifacts.Result

  @supervisor Vxpipe.Artifacts.MetadataPublisherSupervisor

  @spec publish(Result.t(), Configuration.t(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def publish(%Result{} = result, %Configuration{} = configuration, options \\ [])
      when is_list(options) do
    child_options =
      options
      |> Keyword.put(:result, result)
      |> Keyword.put(:configuration, configuration)

    DynamicSupervisor.start_child(@supervisor, {Publisher, child_options})
  end
end
