defmodule Vxpipe.CallEngine.Capability.TextToSpeech.Output do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.CallEngine.Speech.Audio
  alias Vxpipe.CallEngine.TextToSpeechRequest

  @request_timeout 4_000
  @call_timeout 4_500

  def start_link(options) do
    init_options = Keyword.take(options, [:request_timeout])
    GenServer.start_link(__MODULE__, init_options, Keyword.take(options, [:name]))
  end

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
  def init(options) do
    request_timeout = Keyword.get(options, :request_timeout, @request_timeout)
    true = is_integer(request_timeout) and request_timeout > 0
    {:ok, %{output: nil, interrupt: nil, request_timeout: request_timeout}}
  end

  @impl true
  def handle_info({:push, owner, audio, sink, frame}, %{output: nil} = state) do
    {request_id, timer} =
      request(sink, {:vxpipe_audio_output, frame}, state.request_timeout)

    pending = %{
      id: request_id,
      owner: owner,
      reference: audio.request_ref,
      result: {:push, audio},
      timer: timer
    }

    {:noreply, %{state | output: pending}}
  end

  def handle_info({:finish, owner, request_ref, request}, %{output: nil} = state) do
    {request_id, timer} =
      request(
        request.output_sink,
        {:vxpipe_audio_output_finish, request.correlation_id, owner},
        state.request_timeout
      )

    pending = %{
      id: request_id,
      owner: owner,
      reference: request_ref,
      result: :finish,
      timer: timer
    }

    {:noreply, %{state | output: pending}}
  end

  def handle_info(
        {:vxpipe_tts_output_timeout, request_id},
        %{interrupt: %{id: request_id} = pending} = state
      ) do
    result = deadline_result(pending)
    state = retire_interrupted_output(result, pending, state)
    GenServer.reply(pending.from, result)
    {:noreply, %{state | interrupt: nil}}
  end

  def handle_info(
        {:vxpipe_tts_output_timeout, request_id},
        %{output: %{id: request_id} = pending} = state
      ) do
    deliver_output(self(), pending, deadline_result(pending))
    {:noreply, %{state | output: nil}}
  end

  def handle_info(message, state) do
    case response(message, state.interrupt) do
      {:reply, result, pending} ->
        state = retire_interrupted_output(result, pending, state)
        GenServer.reply(pending.from, result)
        {:noreply, %{state | interrupt: nil}}

      :no_reply ->
        case response(message, state.output) do
          {:reply, result, pending} ->
            deliver_output(self(), pending, result)
            {:noreply, %{state | output: nil}}

          :no_reply ->
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_call({:interrupt, request_ref, request, callback}, from, %{interrupt: nil} = state) do
    {request_id, timer} =
      request(
        request.output_sink,
        {:vxpipe_audio_output_interrupt, request.correlation_id, callback},
        state.request_timeout
      )

    pending = %{id: request_id, from: from, reference: request_ref, timer: timer}
    {:noreply, %{state | interrupt: pending}}
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :text_to_speech_output)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp request(server, message, timeout) do
    request_id = :gen.send_request(server, :"$gen_call", message)
    timer = Process.send_after(self(), {:vxpipe_tts_output_timeout, request_id}, timeout)
    {request_id, timer}
  end

  defp response(_message, nil), do: :no_reply

  defp response(message, pending) do
    case :gen.check_response(message, pending.id) do
      {:reply, result} ->
        cancel_timer(pending)
        {:reply, result, pending}

      {:error, _reason} ->
        cancel_timer(pending)
        {:reply, {:error, :sink_unavailable}, pending}

      :no_reply ->
        :no_reply
    end
  end

  defp retire_interrupted_output(
         {:ok, _played_ms},
         %{reference: reference},
         %{output: %{reference: reference} = output} = state
       ) do
    abandon(output)
    %{state | output: nil}
  end

  defp retire_interrupted_output(_result, _pending, state), do: state

  defp deadline_result(pending) do
    case :gen.receive_response(pending.id, 0) do
      {:reply, result} -> result
      {:error, _reason} -> {:error, :sink_unavailable}
      :timeout -> {:error, :sink_unavailable}
    end
  end

  defp abandon(pending) do
    cancel_timer(pending)
    _ = :gen.receive_response(pending.id, 0)
    :ok
  end

  defp cancel_timer(pending) do
    _ = Process.cancel_timer(pending.timer)
    :ok
  end

  defp deliver_output(output, pending, result) do
    result =
      if pending.result == :finish,
        do: {:finish, result},
        else: append(pending.result, result)

    send(pending.owner, {:vxpipe_tts_output, output, pending.reference, result})
  end

  defp append({:push, audio}, result), do: {:push, audio, result}
end
