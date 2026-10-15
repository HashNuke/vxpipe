defmodule Vxpipe.CallEngine.Speech.ContextTTSProvider do
  @moduledoc """
  A context-based realtime synthesis provider sharing one capability-owned
  socket across utterances. Each utterance gets a provider-shaped context
  identity with a provider-backed terminal; wire formats stay provider-owned.
  """

  @callback validate_text(String.t()) :: :ok | {:error, :invalid_text}
  @callback request_configuration(struct()) :: {:ok, struct()} | {:error, atom()}
  @callback connection_options(struct()) :: %{
              url: String.t(),
              headers: [{String.t(), String.t()}]
            }
  @callback new_context_id() :: {:ok, String.t()} | {:error, atom()}
  @callback open_utterance(struct(), String.t(), String.t()) :: [String.t()]
  @callback cancel_utterance(struct(), String.t()) :: String.t() | nil
  @callback close_utterance(struct(), String.t()) :: String.t()
  @callback close_socket(struct()) :: String.t() | nil
  @callback keepalive_payload(struct(), String.t()) :: String.t() | nil
  @callback decode_frame(binary()) ::
              {:ok, {:audio, String.t(), binary()}}
              | {:ok, {:audio_final, String.t(), binary()}}
              | {:ok, {:final, String.t()}}
              | {:ok, :ignore}
              | {:error, atom()}
  @callback validate_audio(binary()) :: {:audio, binary()} | {:error, atom()}
end
