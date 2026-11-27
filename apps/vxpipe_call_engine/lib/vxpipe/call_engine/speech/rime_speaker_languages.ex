defmodule Vxpipe.CallEngine.Speech.RimeSpeakerLanguages do
  @moduledoc """
  Matches Coda language hints to the selected speaker. The static snapshot
  comes from https://users.rime.ai/data/voices/voice_details.json.
  https://docs.rime.ai/docs/voices-coda.md lists voices withheld for correction.
  """

  alias Vxpipe.CallEngine.Speech.ConversationLanguages

  @external_resource Path.expand("../../../../priv/rime_coda_speakers.json", __DIR__)
  @languages for {lang, speakers} <- JSON.decode!(File.read!(@external_resource)),
                 speaker <- speakers,
                 into: %{},
                 do: {speaker, lang}

  # Documented but withheld pending a catalog correction; omit hints.
  @withheld MapSet.new(~w(alfhild pola potrero solana yukiko))

  def hint(preferences, speaker) do
    speaker = speaker || "astra"

    case Map.get(@languages, speaker) do
      nil ->
        []

      language ->
        if MapSet.member?(@withheld, speaker),
          do: [],
          else: ConversationLanguages.resolve_supported(preferences, [language], false)
    end
  end
end
