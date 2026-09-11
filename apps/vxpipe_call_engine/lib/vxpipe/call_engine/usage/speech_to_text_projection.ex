defmodule Vxpipe.CallEngine.Usage.SpeechToTextProjection do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.CallEngine.Usage.SpeechToTextSession

  alias Vxpipe.CallEngine.Usage.{
    Attribution,
    Measurement,
    Observation
  }

  @spec started(SpeechToTextSession.t(), DateTime.t()) :: [Observation.t()]
  def started(%SpeechToTextSession{} = session, %DateTime{} = observed_at) do
    build(
      session,
      "session",
      session.started_source_sequence,
      nil,
      "started",
      :in_progress,
      observed_at
    )
  end

  @spec final_turn(SpeechToTextSession.t(), Signal.t(), boolean(), DateTime.t()) ::
          [Observation.t()]
  def final_turn(
        %SpeechToTextSession{} = session,
        %Signal{} = signal,
        retain_text_measurement?,
        %DateTime{} = observed_at
      )
      when is_boolean(retain_text_measurement?) do
    signal
    |> measurements(retain_text_measurement?)
    |> Enum.flat_map(fn measurement ->
      component = if measurement == nil, do: "operation", else: measurement.component

      build(
        session,
        signal.provider_turn_index,
        signal.provider_sequence,
        measurement,
        component,
        :succeeded,
        observed_at
      )
    end)
  end

  @spec terminal(
          SpeechToTextSession.t(),
          :succeeded | :failed | :cancelled,
          DateTime.t()
        ) :: [Observation.t()]
  def terminal(%SpeechToTextSession{} = session, outcome, %DateTime{} = observed_at)
      when outcome in [:succeeded, :failed, :cancelled] do
    build(session, "session", nil, nil, "terminal", outcome, observed_at)
  end

  defp measurements(signal, retain_text_measurement?) do
    measurements =
      []
      |> maybe_add_audio_duration(signal.audio_duration_ms)
      |> maybe_add_text_characters(signal.text, retain_text_measurement?)
      |> Enum.reverse()

    if measurements == [], do: [nil], else: measurements
  end

  defp maybe_add_audio_duration(measurements, milliseconds)
       when is_integer(milliseconds) and milliseconds >= 0 do
    [
      measurement!("recognized_audio_duration", :milliseconds, milliseconds, :provider_reported)
      | measurements
    ]
  end

  defp maybe_add_audio_duration(measurements, _unknown), do: measurements

  defp maybe_add_text_characters(measurements, text, true) when is_binary(text) do
    [
      measurement!(
        "recognized_text_characters",
        :characters,
        String.length(text),
        :locally_measured
      )
      | measurements
    ]
  end

  defp maybe_add_text_characters(measurements, _text, _retain?), do: measurements

  defp measurement!(component, unit, quantity, provenance) do
    {:ok, measurement} =
      Measurement.new(
        component: component,
        unit: unit,
        quantity: quantity,
        mode: :delta,
        status: :final,
        provenance: provenance
      )

    measurement
  end

  defp build(
         session,
         turn_identity,
         source_sequence,
         measurement,
         component,
         outcome,
         observed_at
       ) do
    with {:ok, attribution} <- attribution(session),
         {:ok, observation} <-
           Observation.new(
             id: observation_id(session.attempt_id, turn_identity, component),
             source_sequence: source_sequence,
             tenant_id: Map.fetch!(session.identity, :tenant_id),
             call_id: session.call_id,
             attempt_id: session.attempt_id,
             capability: :speech_to_text,
             provider: session.provider,
             attribution: attribution,
             measurement: measurement,
             outcome: outcome,
             observed_at: observed_at
           ) do
      [observation]
    else
      _invalid -> []
    end
  end

  defp attribution(session) do
    Attribution.new(
      room_id: Map.get(session.identity, :room_id),
      incarnation_id: Map.get(session.identity, :incarnation_id),
      participant_id: Map.get(session.identity, :participant_id),
      activation_id: session.activation_id,
      service_interval_id: session.service_interval_id
    )
  end

  defp observation_id(attempt_id, turn_identity, component) do
    digest = :crypto.hash(:sha256, "#{attempt_id}:#{turn_identity}:#{component}")
    "uobs_" <> Base.url_encode64(digest, padding: false)
  end
end
