defmodule Vxpipe.Artifacts.RecordingWriter.Handle do
  @moduledoc false

  alias Vxpipe.Artifacts.Handoff

  @enforce_keys [:writer, :handoff, :channels]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          writer: pid(),
          handoff: Handoff.t(),
          channels: pos_integer()
        }
end
