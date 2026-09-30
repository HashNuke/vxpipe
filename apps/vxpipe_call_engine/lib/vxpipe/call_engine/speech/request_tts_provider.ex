defmodule Vxpipe.CallEngine.Speech.RequestTTSProvider do
  @moduledoc "Private configuration and phrase validation for owned request TTS."
  alias Vxpipe.CallEngine.Speech.Descriptor

  @callback request_configuration(struct()) ::
              {:ok, Descriptor.t(), module()} | {:error, :invalid_configuration}
  @callback validate_text(term()) :: :ok | {:error, :invalid_text}
end
