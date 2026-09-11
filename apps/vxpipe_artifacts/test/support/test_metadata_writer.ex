defmodule Vxpipe.Artifacts.TestMetadataWriter do
  @moduledoc false

  @behaviour Vxpipe.Artifacts.Metadata.Writer

  @impl true
  def write(options, result) do
    observer = Keyword.fetch!(options, :observer)
    reference = make_ref()
    send(observer, {:test_artifact_metadata_write, self(), reference, result})

    receive do
      {:test_artifact_metadata_result, ^reference, outcome} -> outcome
    end
  end
end
