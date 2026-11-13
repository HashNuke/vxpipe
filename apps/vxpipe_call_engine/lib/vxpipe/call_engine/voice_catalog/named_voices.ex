defmodule Vxpipe.CallEngine.VoiceCatalog.NamedVoices do
  @moduledoc "Documented named voices for installed speech adapters; no remote discovery or synthesis."
  alias Vxpipe.CallEngine.VoiceCatalog.Query

  # Sources and model restrictions: docs/design/provider-voice-picker.md.
  @google ~w(Zephyr Puck Charon Kore Fenrir Leda Orus Aoede Callirrhoe Autonoe Enceladus Iapetus Umbriel Algieba Despina Erinome Algenib Rasalgethi Laomedeia Achernar Alnilam Schedar Gacrux Pulcherrima Achird Zubenelgenubi Vindemiatrix Sadachbia Sadaltager Sulafat)
  @openai ~w(alloy ash ballad beacon bossa brise calandria cedar cinder compas coral delta destello echo flitz gleam halo harema hornero juni luciernaga marin meridian nira noeul nuri pearl quartz ripple sage shida shimmer sillage stone tempo verse vesper willow)
  @flux ~w(hannah kit alexis cliff sienna cole brooke colin gemma haley heather miles sean bree brittany bruce conor donovan drew elise jack kai kelsey maeve marcelo marcus meena meghan naveen paige priya rufus sharon tanner wade wes)

  def filters, do: []
  def list(scope, query, _payload, _options), do: Query.page(entries(scope), query)
  def get(scope, id, _payload, _options), do: {:ok, Enum.find(entries(scope), &(&1.id == id))}

  defp entries(%{provider: "google", model: model})
       when model in ["gemini-3.1-flash-tts-preview", "gemini-3.8-live"],
       do: Enum.map(@google, &%{id: &1, name: &1, attributes: []})

  defp entries(%{provider: "openai", model: "gpt-live-1"}), do: named(@openai)
  defp entries(%{provider: "deepgram", model: "flux"}), do: named(@flux)
  defp entries(_), do: []
  defp named(names), do: Enum.map(names, &%{id: &1, name: String.capitalize(&1), attributes: []})
end
