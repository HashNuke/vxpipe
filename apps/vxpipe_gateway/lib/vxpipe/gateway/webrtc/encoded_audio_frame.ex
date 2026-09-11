defmodule Vxpipe.Gateway.WebRTC.EncodedAudioFrame do
  @moduledoc false

  @enforce_keys [:payload, :pcm]
  defstruct @enforce_keys

  @type t :: %__MODULE__{payload: binary(), pcm: binary()}
end
