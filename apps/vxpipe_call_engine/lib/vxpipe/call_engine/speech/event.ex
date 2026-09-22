defmodule Vxpipe.CallEngine.Speech.Event do
  @moduledoc """
  A semantic speech event. The channel stamps session identity, producer and order.
  Consumers must successfully call `Speech.Session.ack/2` before acting on live
  semantic fields. An attached TTS usage snapshot is immutable historical
  evidence and remains valid if the live event is later revoked. Transcript text
  and provider identifiers are excluded from inspection.
  """

  alias Vxpipe.CallEngine.Speech.{Channel, ToolArguments}

  @maximum_text_bytes 65_536

  @derive {Inspect, only: [:kind, :session, :sequence, :turn_ref]}
  defstruct [
    :session,
    :generation,
    :producer,
    :sequence,
    :kind,
    :request_ref,
    :provenance,
    :turn_ref,
    :text,
    :provider_request_id,
    :audio_duration_ms,
    :usage,
    :readiness,
    :endpointing,
    :reason,
    :call_ref,
    :tool_name,
    :arguments
  ]

  @type t :: %__MODULE__{}

  @doc "Publish one bounded semantic event; `:discarded` means a prepared session was still fenced."
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

  def supported?(%__MODULE__{kind: :speech_started}, %{kind: kind} = descriptor)
      when kind in [:stt, :sts],
      do: descriptor.speech_start?

  def supported?(%__MODULE__{kind: :turn_resumed}, %{kind: kind} = descriptor)
      when kind in [:stt, :sts],
      do: descriptor.resume?

  def supported?(
        %__MODULE__{kind: :eager_turn_ended, endpointing: evidence},
        %{kind: kind} = descriptor
      )
      when kind in [:stt, :sts],
      do: descriptor.eager_end? and descriptor.endpointing == evidence

  def supported?(
        %__MODULE__{kind: :turn_ended, endpointing: evidence},
        %{kind: kind} = descriptor
      )
      when kind in [:stt, :sts],
      do: descriptor.endpointing == evidence

  def supported?(%__MODULE__{kind: :transcript}, %{kind: :stt}),
    do: true

  def supported?(%__MODULE__{kind: :input_transcript}, %{kind: :sts} = descriptor),
    do: descriptor.input_transcript?

  def supported?(%__MODULE__{kind: :output_transcript}, %{kind: :sts} = descriptor),
    do: descriptor.output_transcript?

  def supported?(%__MODULE__{kind: kind}, %{kind: :sts})
      when kind in [:tool_call, :tool_cancelled, :interrupted, :output_completed],
      do: true

  def supported?(
        %__MODULE__{kind: :input_submitted, provenance: provenance},
        %{kind: kind} = descriptor
      )
      when kind in [:tts, :sts],
      do: provenance == descriptor.usage_identity.provenance

  def supported?(%__MODULE__{kind: kind}, %{kind: :tts}) when kind in [:completed, :cancelled],
    do: true

  def supported?(_event, _descriptor), do: false

  defp allowed_fields(:ready), do: [:readiness, :provider_request_id]
  defp allowed_fields(:input_submitted), do: [:request_ref, :provenance, :provider_request_id]
  defp allowed_fields(:failed), do: [:request_ref, :reason]

  defp allowed_fields(kind) when kind in [:completed, :cancelled],
    do: [:request_ref, :provider_request_id]

  defp allowed_fields(:speech_started), do: [:turn_ref, :provider_request_id]
  defp allowed_fields(:turn_resumed), do: [:turn_ref, :provider_request_id]
  defp allowed_fields(:transcript), do: [:turn_ref, :text, :provider_request_id]
  defp allowed_fields(:input_transcript), do: [:turn_ref, :text, :provider_request_id]
  defp allowed_fields(:output_transcript), do: [:turn_ref, :text, :provider_request_id]

  defp allowed_fields(:tool_call),
    do: [:call_ref, :turn_ref, :tool_name, :arguments, :provider_request_id]

  defp allowed_fields(:tool_cancelled), do: [:call_ref, :provider_request_id]
  defp allowed_fields(:interrupted), do: [:turn_ref, :provider_request_id]
  defp allowed_fields(:output_completed), do: [:turn_ref, :request_ref, :provider_request_id]

  defp allowed_fields(kind) when kind in [:turn_ended, :eager_turn_ended],
    do: [:turn_ref, :text, :provider_request_id, :endpointing, :audio_duration_ms]

  defp allowed_fields(_kind), do: []

  defp valid?(event) do
    valid_kind?(event) and
      (is_nil(event.audio_duration_ms) or
         (is_integer(event.audio_duration_ms) and event.audio_duration_ms >= 0)) and
      (is_nil(event.text) or
         (is_binary(event.text) and byte_size(event.text) <= @maximum_text_bytes and
            String.valid?(event.text))) and
      (is_nil(event.provider_request_id) or
         (is_binary(event.provider_request_id) and byte_size(event.provider_request_id) in 1..256 and
            String.valid?(event.provider_request_id)))
  end

  defp valid_kind?(%__MODULE__{kind: :ready, readiness: mode}),
    do: mode in [:initialized, :provider_acknowledged]

  defp valid_kind?(%__MODULE__{
         kind: :input_submitted,
         request_ref: reference,
         provenance: provenance
       }),
       do: is_reference(reference) and provenance in [:locally_measured, :provider_reported]

  defp valid_kind?(%__MODULE__{kind: kind, request_ref: reference})
       when kind in [:completed, :cancelled],
       do: is_reference(reference)

  defp valid_kind?(%__MODULE__{kind: :failed, request_ref: reference, reason: reason}),
    do:
      is_reference(reference) and
        reason in [
          :busy,
          :empty_text,
          :invalid_text,
          :input_too_large,
          :output_too_large,
          :unsupported_character
        ]

  defp valid_kind?(%__MODULE__{kind: kind, turn_ref: reference})
       when kind in [:speech_started, :turn_resumed],
       do: is_reference(reference)

  defp valid_kind?(%__MODULE__{kind: kind, turn_ref: reference, text: text} = event)
       when kind in [:transcript, :turn_ended, :eager_turn_ended],
       do:
         is_reference(reference) and is_binary(text) and
           (kind == :transcript or event.endpointing in [:provider_semantic, :provider_gap])

  defp valid_kind?(%__MODULE__{kind: kind, turn_ref: reference, text: text})
       when kind in [:input_transcript, :output_transcript],
       do: is_reference(reference) and is_binary(text)

  defp valid_kind?(%__MODULE__{
         kind: :tool_call,
         call_ref: reference,
         turn_ref: turn,
         tool_name: name,
         arguments: arguments
       }),
       do:
         is_reference(reference) and is_reference(turn) and is_binary(name) and
           byte_size(name) in 1..256 and String.valid?(name) and ToolArguments.valid?(arguments)

  defp valid_kind?(%__MODULE__{kind: :tool_cancelled, call_ref: reference}),
    do: is_reference(reference)

  defp valid_kind?(%__MODULE__{kind: :interrupted, turn_ref: reference}),
    do: is_reference(reference)

  defp valid_kind?(%__MODULE__{kind: :output_completed, request_ref: reference, turn_ref: turn}),
    do: is_reference(reference) and is_reference(turn)

  defp valid_kind?(_event), do: false
end
