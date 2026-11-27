defmodule Vxpipe.CallEngine.Speech.ModelLanguages do
  @moduledoc "Language selection contracts for installed speech models."

  @flux ~w(en es fr de hi ru pt ja it nl)
  @scribe ~w(af am ar as ast az be bg bn bs ca ceb cs cy da de el en es et fa ff fi fil fr ga gl gu ha he hi hr hu hy id ig is it ja jv ka kea kk km kn ko ku ky lb lg ln lo lt luo lv mi mk ml mn mr ms mt my ne nl no nso ny oc or pa pl ps pt ro ru sd si sk sl sn so sr sv sw ta te tg th tr uk umb ur uz vi wo xh yue zh zu)
  @aliases ~w(afr amh ara asm aze bel ben bos bul cat ces cym dan deu ell eng est fas fin fra ful gle glg guj hau heb hin hrv hun hye ibo ind isl ita jav jpn kan kat kaz khm kir kor kur lao lav lin lit ltz lug mal mar mkd mlt mon mri msa mya nep nld nor nya oci ori pan pol por pus ron rus sin slk slv sna snd som spa srp swa swe tam tel tgk tha tur ukr urd uzb vie wol xho zho zul)
  @realtime ~w(af am ar as ast az be bg bn bs ca ceb ckb cs cy da de el en es et fa ff fi fil fr gl gu ha he hi hr hu hy id is it ja jv ka kam kk kn ko ky lb lg ln lo lt lv mi mk ml mn mr ms mt my ne nl no oc or pa pl ps pt pt-br ro ru sd sk sl sn so sr sv sw ta te tg th tr uk ur uz vi wo yue zh zu)
  @flash ~w(en ja zh de hi fr ko pt it es id nl tr fil pl sv bg ro ar cs el fi hr ms sk da ta uk ru hu no vi)
  @sonic ~w(en de es fr ja pt zh hi ko it nl pl ru sv tr tl bg ro ar cs el fi hr ms sk da ta uk hu no vi bn th he ka id te gu kn ml mr pa)

  def descriptor(:stt, "deepgram", "flux-general-en"), do: field(false, "en", ["en"])

  def descriptor(:stt, "deepgram", model) when model in ["flux", "flux-general-multi"],
    do: field(true, "automatic", @flux)

  def descriptor(:stt, "google", "gemini-3.5-transcribe-live"),
    do: field(true, "automatic", Vxpipe.Providers.Google.STT.languages())

  def descriptor(:stt, "elevenlabs", model)
      when model in ["scribe_v2_realtime", "scribe_v3_live"],
      do: field(false, "automatic", @scribe)

  def descriptor(:stt, "cartesia", "ink-2"), do: field(false, "automatic", [])

  def descriptor(:sts, "elevenlabs", model)
      when model in ["eleven_realtime_v1_mini", "eleven_realtime_v1_max"],
      do: field(false, "en", @realtime)

  def descriptor(:tts, "cartesia", model) when model in ["sonic-3.6", "sonic-3.6-2026-08-27"],
    do:
      field(
        false,
        "provider",
        @sonic ++
          ~w(or ur bg-BG bn-IN cs-CZ da-DK de-DE el-GR en-AU en-CA en-GB en-IE en-IN en-NZ en-SG en-US en-ZA es-ES es-MX es-US fi-FI fr-CA fr-FR gu-IN he-IL hi-IN hr-HR hu-HU id-ID it-IT ja-JP ka-GE kn-IN ko-KR ml-IN mr-IN ms-MY nl-BE nl-NL no-NO or-IN pa-IN pl-PL pt-BR pt-PT ro-RO ru-RU sk-SK sv-SE ta-IN te-IN th-TH tl-PH tr-TR uk-UA ur-IN vi-VN zh-CN)
      )

  def descriptor(:tts, "cartesia", model) when model in ["sonic-3", "sonic-3.5"],
    do: field(false, "provider", @sonic)

  def descriptor(:tts, "elevenlabs", "eleven_flash_v2_5"), do: field(false, "automatic", @flash)

  def descriptor(:tts, "google", "gemini-3.1-flash-tts-preview"),
    do:
      field(
        false,
        "automatic",
        ~w(af-ZA am-ET ar-001 ar-EG az-AZ be-BY bg-BG bn-BD ca-ES ceb-PH cmn-CN cmn-tw cs-CZ da-DK de-DE el-GR en-AU en-GB en-IN en-US es-419 es-ES es-MX et-EE eu-ES fa-IR fi-FI fil-PH fr-CA fr-FR gl-ES gu-IN he-IL hi-IN hr-HR ht-HT hu-HU hy-AM id-ID is-IS it-IT ja-JP jv-JV ka-GE kn-IN ko-KR kok-IN la-VA lb-LU lo-LA lt-LT lv-LV mai-IN mg-MG mk-MK ml-IN mn-MN mr-IN ms-MY my-MM nb-NO ne-NP nl-NL nn-NO or-IN pa-IN pl-PL ps-AF pt-BR pt-PT ro-RO ru-RU sd-IN si-LK sk-SK sl-SI sq-AL sr-RS sv-SE sw-KE ta-IN te-IN th-TH tr-TR uk-UA ur-PK vi-VN)
      )

  def descriptor(:tts, "rime", "coda"), do: field(false, "en", ~w(en es fr pt de ja ar hi it nl))
  def descriptor(:tts, "deepgram", "flux"), do: field(false, "en", ["en"])
  def descriptor(_kind, _provider, _model), do: nil

  def valid?(_kind, _provider, _model, []), do: true

  def valid?(kind, provider, model, codes) when is_list(codes) do
    case descriptor(kind, provider, model) do
      %{multiple: multiple, values: values} ->
        allowed =
          if kind == :stt and provider == "elevenlabs", do: @aliases ++ values, else: values

        (multiple or length(codes) == 1) and Enum.uniq(codes) == codes and
          Enum.all?(codes, &(&1 in allowed))

      nil ->
        false
    end
  end

  def valid?(_kind, _provider, _model, _codes), do: false

  def option(nil), do: []
  def option(code), do: [language: code]

  def put(map, _key, nil), do: map
  def put(map, key, code), do: Map.put(map, key, code)

  defp field(multiple, default, values),
    do: %{multiple: multiple, default: default, values: values}
end
