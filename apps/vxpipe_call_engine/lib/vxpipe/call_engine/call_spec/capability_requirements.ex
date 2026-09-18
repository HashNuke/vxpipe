defmodule Vxpipe.CallEngine.CallSpec.CapabilityRequirements do
  @moduledoc "Effective capability selections and their source paths, including transfer destinations."

  alias Vxpipe.CallEngine.{CallSpec, CapabilityCatalog}
  alias Vxpipe.CallEngine.CallSpec.Capabilities

  def all(%CallSpec{} = call_spec) do
    participants =
      call_spec.participants
      |> Enum.sort_by(fn {ref, _participant} -> ref end)
      |> Enum.flat_map(fn {_ref, participant} ->
        effective(participant, call_spec.default_capabilities)
      end)

    opening =
      case call_spec.opening_audio do
        %{type: :text, text_to_speech: selection} ->
          [{selection, ["opening_audio", "text_to_speech"]}]

        _none ->
          []
      end

    Enum.reject(participants ++ opening, fn {selection, _path} -> is_nil(selection) end)
  end

  def credentials(%CallSpec{} = call_spec) do
    call_spec
    |> all()
    |> Enum.filter(fn {selection, _path} -> CapabilityCatalog.credential_required?(selection) end)
    |> Enum.uniq_by(fn {selection, _path} -> {selection.provider, selection.credential_name} end)
  end

  def effective(participant, defaults) do
    kinds =
      if participant.kind == :human,
        do: [:speech_to_text],
        else: [:model_inference, :text_to_speech]

    Enum.map(kinds, fn kind ->
      case Capabilities.ref(participant.capabilities, kind) do
        nil ->
          {Capabilities.ref(defaults, kind), ["defaults", "capabilities", Atom.to_string(kind)]}

        selection ->
          {selection,
           ["participants", participant.call_spec_key, "capabilities", Atom.to_string(kind)]}
      end
    end)
  end
end
