defmodule Vxpipe.Artifacts.Result do
  @moduledoc "The outcome reported after an artifact writer finishes."

  alias Vxpipe.Artifacts.Manifest

  @enforce_keys [:manifest, :artifact]
  defstruct @enforce_keys

  @type t :: %__MODULE__{manifest: Manifest.t(), artifact: nil | map()}
end
