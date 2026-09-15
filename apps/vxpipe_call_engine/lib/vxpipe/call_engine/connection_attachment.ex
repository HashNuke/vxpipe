defmodule Vxpipe.CallEngine.ConnectionAttachment do
  @moduledoc """
  Internal handles granted to one authorized transport connection.

  This struct is never part of a public snapshot or wire protocol.
  """

  alias Vxpipe.CallEngine.RoomAudioHandle

  @enforce_keys [:room_monitor, :media_ingress]
  defstruct @enforce_keys ++
              [
                admission: :main,
                connection: nil,
                room_audio: nil,
                room_audio_input_mode: :disabled,
                room_audio_output_mode: :disabled,
                transfer_attempt_id: nil
              ]

  @type t :: %__MODULE__{
          room_monitor: reference(),
          media_ingress: pid() | nil,
          admission: :main | :transfer_preparation,
          connection: pid() | nil,
          room_audio: RoomAudioHandle.t() | nil,
          room_audio_input_mode: :disabled | :enabled,
          room_audio_output_mode: :disabled | :full_mix | :mix_minus,
          transfer_attempt_id: nil | String.t()
        }
end
