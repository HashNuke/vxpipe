defmodule Vxpipe.Gateway.Media.AudioOutput.RemotePlayback do
  @moduledoc false

  @timeout 4_000

  def start(state, action, from, played) do
    request = make_ref()
    target = state.playback_control

    send(
      target.socket_owner,
      {:vxpipe_playback_command, target.stream_id, action, self(), request}
    )

    timer = Process.send_after(self(), {:playback_ack_timeout, request}, @timeout)
    pending = %{request: request, timer: timer, action: action, from: from, played: played}
    %{state | remote_playback: pending}
  end

  def complete(state, result) do
    pending = state.remote_playback
    Process.cancel_timer(pending.timer)

    reply =
      case {pending.action, result} do
        {:clear, :ok} -> {:ok, pending.played}
        {:drain, :ok} -> :ok
        {_, _} -> {:error, :playback_unavailable}
      end

    GenServer.reply(pending.from, reply)
    %{state | remote_playback: nil}
  end

  def cancel(%{remote_playback: nil} = state), do: state

  def cancel(state) do
    pending = state.remote_playback
    Process.cancel_timer(pending.timer)
    GenServer.reply(pending.from, {:error, :cleared})
    %{state | remote_playback: nil}
  end
end
