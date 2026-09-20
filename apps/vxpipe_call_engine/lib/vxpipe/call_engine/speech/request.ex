defmodule Vxpipe.CallEngine.Speech.Request do
  @moduledoc """
  An admitted TTS request. `ref` correlates provider events and audio; admission
  alone does not establish provider submission or generated speech.
  """

  @enforce_keys [:session, :ref, :consumer, :input_characters, :usage_identity, :format]
  @derive {Inspect, only: [:session, :ref, :input_characters]}
  defstruct @enforce_keys
  @type t :: %__MODULE__{}

  @doc false
  def new(allocation, reference, consumer, descriptor, text) do
    %__MODULE__{
      session: allocation,
      ref: reference,
      consumer: consumer,
      input_characters: String.length(text),
      usage_identity: descriptor.usage_identity,
      format: descriptor.format
    }
  end
end
