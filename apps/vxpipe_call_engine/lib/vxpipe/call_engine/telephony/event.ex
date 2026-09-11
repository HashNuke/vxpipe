defmodule Vxpipe.CallEngine.Telephony.Event do
  @moduledoc "A provider-neutral, authenticated phone-leg lifecycle or media observation."

  alias Vxpipe.CallEngine.Telephony.MediaPacket

  @kinds [
    :incoming,
    :outgoing,
    :answered,
    :media_started,
    :media,
    :dtmf,
    :answering_machine,
    :ended
  ]
  @answering_machine_results [:human, :machine, :unknown]
  @end_reasons [:hangup, :busy, :no_answer, :failed, :timeout]
  @dtmf ~r/\A[0-9*#A-D]\z/

  @derive {Inspect,
           only: [
             :kind,
             :provider,
             :provider_event_id,
             :provider_connection_id,
             :provider_call_control_id,
             :provider_call_leg_id,
             :provider_call_session_id,
             :leg_id,
             :occurred_at,
             :stream_id,
             :sequence_number,
             :answering_machine,
             :end_reason
           ]}
  @enforce_keys [:kind, :provider, :provider_call_control_id]
  defstruct @enforce_keys ++
              [
                provider_event_id: nil,
                provider_connection_id: nil,
                provider_call_leg_id: nil,
                provider_call_session_id: nil,
                leg_id: nil,
                occurred_at: nil,
                stream_id: nil,
                sequence_number: nil,
                from: nil,
                to: nil,
                digit: nil,
                answering_machine: nil,
                end_reason: nil,
                media: nil
              ]

  @type kind ::
          :incoming
          | :outgoing
          | :answered
          | :media_started
          | :media
          | :dtmf
          | :answering_machine
          | :ended

  @type t :: %__MODULE__{
          kind: kind(),
          provider: atom(),
          provider_event_id: nil | String.t(),
          provider_connection_id: nil | String.t(),
          provider_call_control_id: String.t(),
          provider_call_leg_id: nil | String.t(),
          provider_call_session_id: nil | String.t(),
          leg_id: nil | String.t(),
          occurred_at: nil | DateTime.t(),
          stream_id: nil | String.t(),
          sequence_number: nil | non_neg_integer(),
          from: nil | String.t(),
          to: nil | String.t(),
          digit: nil | String.t(),
          answering_machine: nil | :human | :machine | :unknown,
          end_reason: nil | :hangup | :busy | :no_answer | :failed | :timeout,
          media: nil | MediaPacket.t()
        }

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = event) do
    event.kind in @kinds and is_atom(event.provider) and
      present?(event.provider_call_control_id) and valid_kind?(event)
  end

  defp valid_kind?(%__MODULE__{kind: :incoming} = event),
    do:
      present?(event.from) and present?(event.to) and present?(event.provider_connection_id) and
        webhook_identified?(event)

  defp valid_kind?(%__MODULE__{kind: :outgoing} = event),
    do:
      present?(event.leg_id) and present?(event.from) and present?(event.to) and
        present?(event.provider_connection_id) and webhook_identified?(event)

  defp valid_kind?(%__MODULE__{kind: :answered} = event), do: webhook_identified?(event)

  defp valid_kind?(%__MODULE__{kind: :media_started} = event),
    do: present?(event.stream_id)

  defp valid_kind?(%__MODULE__{kind: :media, media: %MediaPacket{} = media} = event) do
    present?(event.stream_id) and MediaPacket.valid?(media) and
      event.sequence_number == media.sequence_number
  end

  defp valid_kind?(%__MODULE__{kind: :dtmf, digit: digit} = event),
    do: is_binary(digit) and Regex.match?(@dtmf, digit) and webhook_identified?(event)

  defp valid_kind?(%__MODULE__{kind: :answering_machine, answering_machine: result} = event),
    do: result in @answering_machine_results and webhook_identified?(event)

  defp valid_kind?(%__MODULE__{kind: :ended, end_reason: reason} = event),
    do: reason in @end_reasons and webhook_identified?(event)

  defp valid_kind?(%__MODULE__{}), do: false

  defp webhook_identified?(event) do
    present?(event.provider_event_id) and present?(event.provider_call_leg_id) and
      match?(%DateTime{}, event.occurred_at)
  end

  defp present?(value), do: is_binary(value) and value != ""
end
