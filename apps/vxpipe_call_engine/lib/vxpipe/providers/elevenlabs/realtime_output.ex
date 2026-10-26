defmodule Vxpipe.Providers.ElevenLabs.RealtimeOutput do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.{Channel, Event}

  def new(context, index, instructions, fixed) do
    %{
      announced?: false,
      tool_ids: MapSet.new(),
      id: nil,
      turn: make_ref(),
      context: context,
      index: index,
      instructions: instructions,
      fixed: fixed,
      output: nil,
      chunks: :queue.new(),
      bytes: 0,
      awaiting: nil,
      text: nil,
      text_emitted?: false,
      done?: false,
      completed?: false,
      interrupted?: false,
      interrupt_emitted?: false,
      settled?: false,
      had_tools?: false,
      continued?: false,
      continuation?: false
    }
  end

  def audio(%{interrupted?: true} = response, _pcm), do: {:ok, response}
  def audio(%{done?: true}, _pcm), do: {:error, :late_audio}

  def audio(response, pcm) do
    limit = if response.fixed, do: 2_097_152, else: 524_288

    if response.bytes + byte_size(pcm) <= limit,
      do:
        {:ok,
         %{
           response
           | chunks: :queue.in(pcm, response.chunks),
             bytes: response.bytes + byte_size(pcm)
         }},
      else: {:error, :output_overflow}
  end

  def transcript(%{interrupted?: true} = response, _text), do: {:ok, response}
  def transcript(%{text: text} = response, text), do: {:ok, response}
  def transcript(%{text: text}, _new) when not is_nil(text), do: {:error, :changed_final}

  def transcript(response, text) do
    cond do
      not String.valid?(text) -> {:error, :invalid_text}
      response.fixed && words(response.fixed) != words(text) -> {:error, :opening_mismatch}
      true -> {:ok, %{response | text: response.fixed || text}}
    end
  end

  def interrupt(response), do: %{response | interrupted?: true, chunks: :queue.new(), bytes: 0}

  def drain(%{output: nil} = response, _channel), do: {:ok, response}

  def drain(response, channel) do
    with {:ok, response} <- publish_text(response, channel),
         {:ok, response} <- publish_interruption(response, channel) do
      drain_audio(response, channel)
    end
  end

  defp publish_text(%{text: text, text_emitted?: false, interrupted?: false} = response, channel)
       when is_binary(text) do
    case Event.emit(channel, :output_transcript, turn_ref: response.turn, text: text, final: true) do
      :ok -> {:ok, %{response | text_emitted?: true}}
      _failure -> {:error, :delivery_failed}
    end
  end

  defp publish_text(response, _channel), do: {:ok, response}

  defp publish_interruption(
         %{interrupted?: true, done?: true, interrupt_emitted?: false} = response,
         channel
       ) do
    case Event.emit(channel, :interrupted, turn_ref: response.turn) do
      :ok -> {:ok, %{response | interrupt_emitted?: true}}
      _failure -> {:error, :delivery_failed}
    end
  end

  defp publish_interruption(response, _channel), do: {:ok, response}

  defp drain_audio(%{awaiting: credit} = response, _channel) when not is_nil(credit),
    do: {:ok, response}

  defp drain_audio(%{completed?: true} = response, _channel), do: {:ok, response}

  defp drain_audio(%{fixed: fixed, text: nil, interrupted?: false} = response, _channel)
       when is_binary(fixed), do: {:ok, response}

  defp drain_audio(response, channel) do
    case :queue.out(response.chunks) do
      {{:value, pcm}, rest} ->
        case Channel.submit(channel, response.output, pcm) do
          {:ok, credit} ->
            {:ok,
             %{response | chunks: rest, bytes: response.bytes - byte_size(pcm), awaiting: credit}}

          _failure ->
            {:error, :delivery_failed}
        end

      {:empty, _queue} ->
        complete(response, channel)
    end
  end

  defp complete(%{done?: true} = response, channel) do
    if response.interrupted? or response.text_emitted? do
      case Event.emit(channel, :output_completed,
             turn_ref: response.turn,
             request_ref: response.output
           ) do
        :ok -> {:ok, %{response | completed?: true}}
        _failure -> {:error, :delivery_failed}
      end
    else
      {:ok, response}
    end
  end

  defp complete(response, _channel), do: {:ok, response}

  defp words(text),
    do: text |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]+/u, " ") |> String.split()
end
