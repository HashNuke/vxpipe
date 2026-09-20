defmodule Vxpipe.CallEngine.Speech.Playback do
  @moduledoc "Locally confirmed playback, measured relative to a request and its allocation."
  @enforce_keys [:request_ref, :request_played_ms, :session_played_ms]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end
