defmodule Vxpipe.CallEngine.OpeningAudio.Download do
  @moduledoc false

  @derive {Inspect, only: [:content_type]}
  @enforce_keys [:body, :content_type]
  defstruct @enforce_keys

  @type t :: %__MODULE__{body: binary(), content_type: String.t()}
end
