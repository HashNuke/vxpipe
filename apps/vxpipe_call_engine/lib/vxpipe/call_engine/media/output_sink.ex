defmodule Vxpipe.CallEngine.Media.OutputSink do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.AudioOutputFrame

  @call_timeout 15_000

  @spec push(pid(), AudioOutputFrame.t()) :: :ok | {:error, term()}
  def push(sink, %AudioOutputFrame{} = frame) when is_pid(sink) do
    safe_call(sink, {:vxpipe_audio_output, frame})
  end

  @spec finish(pid(), String.t(), pid()) :: :ok | {:error, term()}
  def finish(sink, turn, callback) when is_pid(sink) and is_binary(turn) and is_pid(callback) do
    safe_call(sink, {:vxpipe_audio_output_finish, turn, callback})
  end

  defp safe_call(sink, message) do
    try do
      GenServer.call(sink, message, @call_timeout)
    catch
      :exit, _reason -> {:error, :sink_unavailable}
    end
  end
end
