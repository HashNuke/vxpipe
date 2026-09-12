defmodule Vxpipe.Gateway.Telephony.LegUsageEvent do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.Event

  @type evidence_provenance :: :provider_reported | :locally_measured

  @spec observation_time(Event.t(), DateTime.t()) :: {DateTime.t(), evidence_provenance()}
  def observation_time(
        %Event{
          occurred_at: %DateTime{} = occurred_at,
          occurred_at_provenance: provenance
        },
        %DateTime{}
      )
      when provenance in [:provider_reported, :locally_measured],
      do: {occurred_at, provenance}

  def observation_time(%Event{}, %DateTime{} = fallback),
    do: {fallback, :locally_measured}

  @spec evidence(Event.t(), evidence_provenance()) :: keyword()
  def evidence(%Event{} = event, provenance)
      when provenance in [:provider_reported, :locally_measured] do
    [
      provenance: provenance,
      delivery_id: event.provider_event_id,
      source_sequence: event.sequence_number
    ]
  end

  @spec terminal_outcome(boolean(), Event.end_reason()) :: :succeeded | :failed
  def terminal_outcome(true, :hangup), do: :succeeded
  def terminal_outcome(_connected?, _reason), do: :failed
end
