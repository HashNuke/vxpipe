defmodule Vxpipe.CallEngine.Media.OutputSink do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.CallEngine.Recording.EgressHandoff

  @call_timeout 15_000

  @spec push(pid(), AudioOutputFrame.t()) :: :ok | {:error, term()}
  def push(sink, %AudioOutputFrame{} = frame) when is_pid(sink) do
    safe_call(sink, {:vxpipe_audio_output, frame})
  end

  @doc false
  @spec bind_recording(pid(), EgressHandoff.t()) :: :ok | {:error, term()}
  def bind_recording(sink, %EgressHandoff{} = handoff) when is_pid(sink) do
    safe_call(sink, {:vxpipe_bind_recording_egress, handoff})
  end

  @spec finish(pid(), String.t(), pid()) :: :ok | {:error, term()}
  def finish(sink, turn, callback) when is_pid(sink) and is_binary(turn) and is_pid(callback) do
    safe_call(sink, {:vxpipe_audio_output_finish, turn, callback})
  end

  @spec interrupt(pid(), String.t(), pid()) :: {:ok, non_neg_integer()} | {:error, term()}
  def interrupt(sink, turn, callback)
      when is_pid(sink) and is_binary(turn) and is_pid(callback) do
    safe_call(sink, {:vxpipe_audio_output_interrupt, turn, callback})
  end

  defp safe_call(sink, message) do
    try do
      GenServer.call(sink, message, @call_timeout)
    catch
      :exit, _reason -> {:error, :sink_unavailable}
    end
  end
end
