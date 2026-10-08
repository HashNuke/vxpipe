defmodule Vxpipe.CallEngine.Speech.Model do
  @moduledoc "Public model and voice descriptors shared by speech adapters and authoring catalogs."

  @type voice :: %{id: String.t(), name: String.t(), default: boolean()}
  @type voices ::
          nil
          | %{type: :free_text, default: String.t(), parameter: String.t()}
          | %{type: :list, values: [voice()], parameter: String.t()}
  @type t :: %{id: String.t(), name: String.t(), default: boolean(), voices: voices()}

  @spec new(String.t(), String.t(), boolean(), voices()) :: t()
  def new(id, name, default, voices \\ nil),
    do: %{id: id, name: name, default: default, voices: voices}

  @spec free_voice(String.t(), String.t()) :: voices()
  def free_voice(default, parameter \\ "voice"),
    do: %{type: :free_text, default: default, parameter: parameter}

  @spec supported?([t()], term()) :: boolean()
  def supported?(models, id), do: Enum.any?(models, &(&1.id == id))
end
