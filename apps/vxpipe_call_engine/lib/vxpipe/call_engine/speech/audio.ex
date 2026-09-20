defmodule Vxpipe.CallEngine.Speech.Audio do
  @moduledoc """
  One request-scoped PCM chunk. Validate before sink use and acknowledge only
  after bounded sink acceptance. Validation does not assert audible playback.
  """
  @enforce_keys [:session, :request_ref, :producer, :sequence, :ref, :payload]
  @derive {Inspect, only: [:session, :request_ref, :sequence, :ref]}
  defstruct @enforce_keys ++ [usage: nil]
  @type t :: %__MODULE__{}
end
