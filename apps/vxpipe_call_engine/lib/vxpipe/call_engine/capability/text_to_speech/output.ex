defmodule Vxpipe.CallEngine.Capability.TextToSpeech.Output do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.CallEngine.Speech.Audio
  alias Vxpipe.CallEngine.TextToSpeechRequest

  @call_timeout 15_000

  def start_link(options),
    do: GenServer.start_link(__MODULE__, nil, Keyword.take(options, [:name]))

  def push(output, owner, %Audio{} = audio, sink, %AudioOutputFrame{} = frame)
      when is_pid(output) and is_pid(owner) and is_pid(sink) do
    send(output, {:push, owner, audio, sink, frame})
    :ok
  end

  def finish(output, owner, request_ref, %TextToSpeechRequest{} = request)
      when is_pid(output) and is_pid(owner) and is_reference(request_ref) do
    send(output, {:finish, owner, request_ref, request})
    :ok
  end

  def interrupt(output, request_ref, %TextToSpeechRequest{} = request, callback)
      when is_pid(output) and is_reference(request_ref) and is_pid(callback) do
    GenServer.call(output, {:interrupt, request_ref, request, callback}, @call_timeout)
  catch
    :exit, _reason -> {:error, :sink_unavailable}
  end

  @impl true
  def init(nil), do: {:ok, %{output: nil, interrupt: nil}}

  @impl true
  def handle_info({:push, owner, audio, sink, frame}, %{output: nil} = state) do
    request_id = request(sink, {:vxpipe_audio_output, frame})

    pending = %{
      id: request_id,
      owner: owner,
      reference: audio.request_ref,
      result: {:push, audio}
    }

    {:noreply, %{state | output: pending}}
  end

  def handle_info({:finish, owner, request_ref, request}, %{output: nil} = state) do
    request_id =
      request(request.output_sink, {:vxpipe_audio_output_finish, request.correlation_id, owner})

    pending = %{id: request_id, owner: owner, reference: request_ref, result: :finish}
    {:noreply, %{state | output: pending}}
  end

  def handle_info(message, state) do
    case response(message, state.interrupt) do
      {:reply, result, pending} ->
        GenServer.reply(pending.from, result)
        {:noreply, %{state | interrupt: nil}}

      :no_reply ->
        case response(message, state.output) do
          {:reply, result, pending} ->
            result =
              if pending.result == :finish,
                do: {:finish, result},
                else: append(pending.result, result)

            send(pending.owner, {:vxpipe_tts_output, self(), pending.reference, result})
            {:noreply, %{state | output: nil}}

          :no_reply ->
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_call({:interrupt, request_ref, request, callback}, from, %{interrupt: nil} = state) do
    request_id =
      request(
        request.output_sink,
        {:vxpipe_audio_output_interrupt, request.correlation_id, callback}
      )

    {:noreply, %{state | interrupt: %{id: request_id, from: from, reference: request_ref}}}
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :text_to_speech_output)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp request(server, message), do: :gen.send_request(server, :"$gen_call", message)

  defp response(_message, nil), do: :no_reply

  defp response(message, pending) do
    case :gen.check_response(message, pending.id) do
      {:reply, result} -> {:reply, result, pending}
      {:error, _reason} -> {:reply, {:error, :sink_unavailable}, pending}
      :no_reply -> :no_reply
    end
  end

  defp append({:push, audio}, result), do: {:push, audio, result}
end
