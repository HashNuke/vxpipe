defmodule Vxpipe.CallEngine.Speech.Event do
  @moduledoc """
  A semantic speech event. The channel stamps session identity, producer and order.
  Consumers must successfully call `Speech.Session.ack/2` before using an event.
  Transcript text and provider identifiers are excluded from inspection.
  """

  alias Vxpipe.CallEngine.Speech.Channel

  @derive {Inspect, only: [:kind, :session, :sequence, :turn_ref]}
  defstruct [
    :session,
    :generation,
    :producer,
    :sequence,
    :kind,
    :turn_ref,
    :text,
    :provider_request_id,
    :readiness,
    :endpointing
  ]

  @type t :: %__MODULE__{}

  @doc "Publish one bounded semantic event from the bound provider process."
  def emit(channel, kind, fields \\ []), do: Channel.emit(channel, kind, fields)

  @doc false
  def build(kind, fields) when is_list(fields) do
    if Keyword.keyword?(fields) and
         Enum.all?(Keyword.keys(fields), &(&1 in allowed_fields(kind))) and
         length(Keyword.keys(fields)) == length(Enum.uniq(Keyword.keys(fields))) do
      event = struct(__MODULE__, Keyword.put(fields, :kind, kind))
      if valid?(event), do: {:ok, event}, else: {:error, :invalid_event}
    else
      {:error, :invalid_event}
    end
  end

  def build(_kind, _fields), do: {:error, :invalid_event}

  @doc false
  def supported?(%__MODULE__{kind: :ready, readiness: readiness}, descriptor),
    do: descriptor.readiness == readiness

  def supported?(%__MODULE__{kind: :speech_started}, descriptor), do: descriptor.speech_start?
  def supported?(%__MODULE__{kind: :turn_resumed}, descriptor), do: descriptor.resume?

  def supported?(%__MODULE__{kind: :eager_turn_ended, endpointing: evidence}, descriptor),
    do: descriptor.eager_end? and descriptor.endpointing == evidence

  def supported?(%__MODULE__{kind: :turn_ended, endpointing: evidence}, descriptor),
    do: descriptor.endpointing == evidence

  def supported?(%__MODULE__{kind: :transcript}, _descriptor), do: true
  def supported?(_event, _descriptor), do: false

  defp allowed_fields(:ready), do: [:readiness, :provider_request_id]
  defp allowed_fields(:speech_started), do: [:turn_ref, :provider_request_id]
  defp allowed_fields(:turn_resumed), do: [:turn_ref, :provider_request_id]
  defp allowed_fields(:transcript), do: [:turn_ref, :text, :provider_request_id]

  defp allowed_fields(kind) when kind in [:turn_ended, :eager_turn_ended],
    do: [:turn_ref, :text, :provider_request_id, :endpointing]

  defp allowed_fields(_kind), do: []

  defp valid?(event) do
    valid_kind?(event) and
      (is_nil(event.text) or
         (is_binary(event.text) and byte_size(event.text) <= 4_096 and String.valid?(event.text))) and
      (is_nil(event.provider_request_id) or
         (is_binary(event.provider_request_id) and byte_size(event.provider_request_id) in 1..256 and
            String.valid?(event.provider_request_id)))
  end

  defp valid_kind?(%__MODULE__{kind: :ready, readiness: mode}),
    do: mode in [:initialized, :provider_acknowledged]

  defp valid_kind?(%__MODULE__{kind: kind, turn_ref: reference})
       when kind in [:speech_started, :turn_resumed],
       do: is_reference(reference)

  defp valid_kind?(%__MODULE__{kind: kind, turn_ref: reference, text: text} = event)
       when kind in [:transcript, :turn_ended, :eager_turn_ended],
       do:
         is_reference(reference) and is_binary(text) and
           (kind == :transcript or event.endpointing in [:provider_semantic, :provider_gap])

  defp valid_kind?(_event), do: false
end
