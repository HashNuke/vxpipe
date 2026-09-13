defmodule Vxpipe.CallEngine.WaitSounds.PreparedAssets do
  @moduledoc "Immutable normalized audio pinned for a call, shared by independent listener players."

  alias Vxpipe.CallEngine.OpeningAudio.Asset

  @derive {Inspect, only: [:profile]}
  @enforce_keys [:slots, :assets, :connection_cue, :profile]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          slots: %{atom() => binary() | nil},
          assets: %{binary() => Asset.t()},
          connection_cue: binary(),
          profile: String.t()
        }
end
