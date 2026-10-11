defmodule Vxpipe.CallEngine.SpeechRecognizerTestConfig do
  @moduledoc "Extract selected recognizer configuration for provider authentication tests."
  alias Vxpipe.CallEngine.Speech.ConversationalSTT

  def native(%{provider: {ConversationalSTT, options}, provider_private: private} = runtime),
    do: %{
      runtime
      | provider: {Keyword.fetch!(options, :provider), Keyword.fetch!(options, :options)},
        provider_private: Keyword.fetch!(private, :recognizer_private)
    }

  def native(runtime), do: runtime
end
