defmodule Vxpipe.CallEngine.Speech.OutputState do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.{Audio, Event, Playback, Request, TTSUsage}

  @maximum_audio_bytes 131_072

  defstruct request: nil,
            pending_audio: nil,
            audio_sequence: 0,
            session_played_ms: 0

  def new, do: %__MODULE__{}

  def admit(%__MODULE__{request: nil} = output, allocation, consumer, descriptor, reference, text) do
    handle = Request.new(allocation, reference, consumer, descriptor, text)

    request = %{
      ref: reference,
      input_characters: handle.input_characters,
      usage_identity: handle.usage_identity,
      provider_request_id: nil,
      provenance: nil,
      submitted?: false,
      submitted_acked?: false,
      terminal?: false,
      terminal_result: nil,
      fenced?: false,
      rejected?: false,
      awaiting: nil,
      generated_bytes: 0,
      accepted_bytes: 0,
      uncredited_bytes: 0,
      played_ms: 0
    }

    {:ok, handle, %{output | request: request, pending_audio: nil}}
  end

  def admit(%__MODULE__{}, _allocation, _consumer, _descriptor, _reference, _text),
    do: {:error, :busy}

  def prepare_audio(%__MODULE__{} = output, allocation, producer, reference, audio) do
    cond do
      not valid_audio?(audio) ->
        {:error, :invalid_audio}

      not open?(output, reference) or not output.request.submitted? ->
        {:error, :stale_request}

      not is_nil(output.request.awaiting) ->
        {:error, :busy}

      true ->
        envelope = %Audio{
          session: allocation,
          request_ref: reference,
          producer: producer,
          sequence: output.audio_sequence + 1,
          ref: make_ref(),
          payload: audio
        }

        {:ok, envelope}
    end
  end

  def await_audio(%__MODULE__{} = output, envelope, timer, deadline, usage?) do
    request = %{
      output.request
      | generated_bytes: output.request.generated_bytes + byte_size(envelope.payload)
    }

    usage = if usage?, do: TTSUsage.snapshot(envelope.session, request)
    envelope = %{envelope | usage: usage}
    awaiting = %{audio: envelope, timer: timer, deadline: deadline}
    request = %{request | awaiting: awaiting}

    %{
      output
      | request: request,
        pending_audio: envelope,
        audio_sequence: envelope.sequence
    }
  end

  def current_audio?(%__MODULE__{} = output, audio, now) do
    case output.request do
      %{
        fenced?: false,
        terminal?: false,
        submitted_acked?: true,
        awaiting: %{audio: expected, deadline: deadline}
      } ->
        audio == expected and deadline > now

      _request ->
        false
    end
  end

  def acknowledge_audio(%__MODULE__{} = output, audio, now) do
    if current_audio?(output, audio, now) do
      awaiting = output.request.awaiting

      request = %{
        output.request
        | awaiting: nil,
          accepted_bytes: output.request.accepted_bytes + byte_size(audio.payload)
      }

      {:ok, awaiting, %{output | request: request}}
    else
      {:error, :stale_audio}
    end
  end

  def audio_operation(%__MODULE__{} = output, :validate, audio, now) do
    if current_audio?(output, audio, now), do: {:ok, output}, else: {:error, :stale_audio}
  end

  def audio_operation(%__MODULE__{} = output, :ack, audio, now) do
    case acknowledge_audio(output, audio, now) do
      {:ok, awaiting, output} -> {:credit, awaiting, output}
      error -> error
    end
  end

  def audio_operation(%__MODULE__{}, _operation, _audio, _now), do: {:error, :stale_audio}

  def mark_submitted(
        %__MODULE__{} = output,
        %Event{
          request_ref: reference,
          provider_request_id: provider_request_id,
          provenance: provenance
        }
      ) do
    case output.request do
      %{ref: ^reference, terminal?: false, submitted?: false} = request ->
        request = %{
          request
          | submitted?: true,
            provider_request_id: provider_request_id,
            provenance: provenance
        }

        {:ok, %{output | request: request}}

      _request ->
        {:error, :stale_request}
    end
  end

  def mark_submission_acked(%__MODULE__{} = output, reference) do
    case output.request do
      %{ref: ^reference} = request -> %{output | request: %{request | submitted_acked?: true}}
      _request -> output
    end
  end

  def complete(%__MODULE__{} = output, %Event{request_ref: reference} = event) do
    case output.request do
      %{ref: ^reference, fenced?: true} ->
        {:error, :cancelled}

      %{ref: ^reference, terminal?: false, submitted?: true, awaiting: nil} = request ->
        with {:ok, request} <- merge_provider_request_id(request, event.provider_request_id) do
          {:ok, %{output | request: %{request | terminal?: true, terminal_result: :completed}}}
        end

      %{ref: ^reference, terminal?: false} ->
        {:error, :output_pending}

      _request ->
        {:error, :stale_request}
    end
  end

  def mark_terminal(%__MODULE__{} = output, %Event{request_ref: reference} = event) do
    case output.request do
      %{ref: ^reference, fenced?: true, terminal?: false} = request ->
        with {:ok, request} <- merge_provider_request_id(request, event.provider_request_id) do
          {:ok, %{output | request: %{request | terminal?: true, terminal_result: :cancelled}}}
        end

      _request ->
        {:error, :stale_request}
    end
  end

  def fence(%__MODULE__{} = output, reference) do
    case output.request do
      %{ref: ^reference, fenced?: false} = request ->
        awaiting = request.awaiting
        uncredited = if awaiting, do: byte_size(awaiting.audio.payload), else: 0

        request = %{
          request
          | fenced?: true,
            awaiting: nil,
            uncredited_bytes: uncredited
        }

        {:ok, awaiting, %{output | request: request, pending_audio: nil}}

      _request ->
        {:error, :stale_request}
    end
  end

  def record_playback(%__MODULE__{} = output, reference, played_ms, format) do
    case output.request do
      %{ref: ^reference, fenced?: true} = request ->
        maximum =
          div(
            (request.accepted_bytes + request.uncredited_bytes) * 1_000,
            format.sample_rate * 2
          )

        if is_integer(played_ms) and played_ms >= request.played_ms and played_ms <= maximum do
          total = output.session_played_ms + played_ms - request.played_ms

          playback = %Playback{
            request_ref: reference,
            request_played_ms: played_ms,
            session_played_ms: total
          }

          {:ok, playback,
           %{output | request: %{request | played_ms: played_ms}, session_played_ms: total}}
        else
          {:error, :invalid_playback}
        end

      _request ->
        {:error, :invalid_playback}
    end
  end

  def reject(%__MODULE__{} = output, reference, retain?) do
    case output.request do
      %{ref: ^reference, submitted?: false} = request ->
        request = if retain?, do: %{request | rejected?: true, terminal?: true}, else: nil
        {:ok, %{output | request: request}}

      _request ->
        {:error, :already_submitted}
    end
  end

  def settle(%__MODULE__{} = output, reference) do
    case output.request do
      %{ref: ^reference, terminal?: true} ->
        {:ok, %{output | request: nil, pending_audio: nil}}

      _request ->
        {:error, :stale_request}
    end
  end

  def take_pending(%__MODULE__{} = output),
    do: {output.pending_audio, %{output | pending_audio: nil}}

  defp open?(
         %__MODULE__{request: %{ref: reference, fenced?: false, terminal?: false}},
         reference
       ),
       do: true

  defp open?(%__MODULE__{}, _reference), do: false

  defp merge_provider_request_id(request, nil), do: {:ok, request}

  defp merge_provider_request_id(%{provider_request_id: nil} = request, provider_request_id),
    do: {:ok, %{request | provider_request_id: provider_request_id}}

  defp merge_provider_request_id(
         %{provider_request_id: provider_request_id} = request,
         provider_request_id
       ),
       do: {:ok, request}

  defp merge_provider_request_id(_request, _provider_request_id),
    do: {:error, :invalid_event}

  defp valid_audio?(audio),
    do:
      is_binary(audio) and byte_size(audio) in 1..@maximum_audio_bytes and
        rem(byte_size(audio), 2) == 0
end
