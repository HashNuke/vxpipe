defmodule Vxpipe.CallEngine.Provider.TextToSpeech.Signal do
  @moduledoc false

  @enforce_keys [:kind]
  defstruct [
    :kind,
    :request_id,
    :provider_speech_id,
    :provider_code,
    :audio_played_ms,
    :text_spoken,
    :text_remaining
  ]

  @type kind ::
          :connected
          | :speech_started
          | :flushed
          | :speech_completed
          | :speech_interrupted
          | :warning
          | :failed

  @type t :: %__MODULE__{
          kind: kind(),
          request_id: String.t() | nil,
          provider_speech_id: String.t() | nil,
          provider_code: String.t() | nil,
          audio_played_ms: non_neg_integer() | nil,
          text_spoken: String.t() | nil,
          text_remaining: String.t() | nil
        }
end
