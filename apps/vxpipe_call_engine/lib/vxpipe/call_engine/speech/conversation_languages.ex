defmodule Vxpipe.CallEngine.Speech.ConversationLanguages do
  @moduledoc "Validates call-wide language preferences and pins supported hints into the resolved speech selections."

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.Speech.ModelLanguages
  alias Vxpipe.CallEngine.Speech.RimeSpeakerLanguages

  @external_resource Path.expand("../../../../priv/conversation_languages.json", __DIR__)
  @tags @external_resource |> File.read!() |> JSON.decode!()
  @allowed MapSet.new(@tags)
  @speech_kinds %{
    speech_to_text: :stt,
    output_speech_to_text: :stt,
    speech_to_speech: :sts,
    text_to_speech: :tts
  }

  def supported_tags, do: @tags

  def validate(values) when is_list(values) and length(values) <= length(@tags) do
    if Enum.all?(values, &MapSet.member?(@allowed, &1)) and Enum.uniq(values) == values,
      do: {:ok, values},
      else: :error
  end

  def validate(_), do: :error

  def pin(plan, nil), do: plan

  def pin(%ResolvedCallPlan{} = plan, preferences) do
    participants =
      Map.new(plan.participants, fn {key, participant} ->
        capabilities =
          Enum.reduce(@speech_kinds, participant.capabilities, fn {field, kind}, acc ->
            Map.update!(acc, field, &pin_selection(&1, kind, preferences))
          end)

        {key, %{participant | capabilities: capabilities}}
      end)

    opening =
      case plan.opening_audio do
        nil -> nil
        audio -> %{audio | text_to_speech: pin_selection(audio.text_to_speech, :tts, preferences)}
      end

    %{plan | participants: participants, opening_audio: opening}
  end

  defp pin_selection(nil, _, _), do: nil

  defp pin_selection(%CapabilitySelection{} = selection, kind, preferences) do
    model =
      if {kind, selection.provider, selection.model} == {:stt, "deepgram", "flux"},
        do: "flux-general-multi",
        else: selection.model

    options =
      if kind == :stt and selection.provider == "elevenlabs",
        do: Map.delete(selection.options, "language_code"),
        else: selection.options

    languages =
      case {kind, selection.provider, model} do
        {:tts, "rime", "coda"} ->
          RimeSpeakerLanguages.hint(preferences, Map.get(options, "speaker"))

        _ ->
          resolve(preferences, kind, selection.provider, model)
      end

    selection
    |> Map.put(:languages, languages)
    |> Map.put(:model, model)
    |> Map.put(:options, options)
  end

  def resolve(preferences, _, _, _) when preferences in [nil, []], do: []
  def resolve(_, :stt, "deepgram", "flux-general-en"), do: []
  def resolve(_, :tts, "deepgram", "flux"), do: []
  # Coda voices each serve one language; hints follow the selected speaker
  # (default astra/English) instead of assuming English for every voice.
  def resolve(preferences, :tts, "rime", "coda"),
    do: RimeSpeakerLanguages.hint(preferences, nil)

  def resolve(preferences, :stt, "elevenlabs", model)
      when model in ["scribe_v2_realtime", "scribe_v3_live"] do
    %{values: values} = ModelLanguages.descriptor(:stt, "elevenlabs", model)

    preferences
    |> Enum.map(&scribe_language/1)
    |> resolve_supported(values, true)
  end

  def resolve(preferences, kind, provider, model) do
    case ModelLanguages.descriptor(kind, provider, model) do
      nil -> []
      %{values: values, multiple: multiple} -> resolve_supported(preferences, values, multiple)
    end
  end

  def resolve_supported(preferences, values, multiple) do
    lookup = Map.new(values, fn code -> {String.downcase(code), code} end)

    codes =
      preferences
      |> Enum.map(fn tag ->
        key = String.downcase(tag)
        lookup[key] || lookup[key |> String.split("-", parts: 2) |> hd()]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if multiple, do: codes, else: Enum.take(codes, 1)
  end

  # Scribe uses zh for Mandarin and a separate yue code for Cantonese.
  defp scribe_language("cmn"), do: "zh"
  defp scribe_language("cmn-" <> _), do: "zh"
  defp scribe_language(tag), do: tag
end
