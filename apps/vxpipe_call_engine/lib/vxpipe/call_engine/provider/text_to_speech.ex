defmodule Vxpipe.CallEngine.Provider.TextToSpeech do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.TextToSpeech.Signal

  @callback new(keyword()) :: {:ok, struct()} | {:error, :invalid_configuration}
  @callback connection_options(struct()) :: map()
  @callback media_format(struct()) :: map()
  @callback encode_speak(String.t()) :: binary()
  @callback encode_flush() :: binary()
  @callback encode_interrupt(non_neg_integer()) :: binary()
  @callback decode(binary()) :: {:ok, Signal.t()} | {:ignore, atom()} | {:error, atom()}
  @callback decode_audio(binary()) :: {:audio, binary()} | {:error, atom()}
end
