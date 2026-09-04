defmodule Vxpipe.CallEngine.Provider.TextToSpeech.Signal do
  @moduledoc false

  @enforce_keys [:kind]
  defstruct [:kind, :request_id, :provider_speech_id, :provider_code]

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
          provider_code: String.t() | nil
        }
end
