defmodule Vxpipe.Gateway.Telephony.PlaybackMarks do
  @moduledoc false

  @derive {Inspect, only: []}
  defstruct pending: nil

  def command(%__MODULE__{pending: pending}, _provider, _stream, :drain, _receiver, _request)
      when not is_nil(pending), do: {:error, :busy}

  def command(%__MODULE__{} = state, provider, stream, action, receiver, request)
      when action in [:drain, :clear] and is_pid(receiver) and is_reference(request) do
    if state.pending, do: reply(state.pending, {:error, :cleared})
    name = "vxpipe-" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    mark = envelope(provider, stream, "mark") |> Map.put("mark", %{"name" => name})
    frames = if action == :clear, do: [envelope(provider, stream, "clear"), mark], else: [mark]
    state = %{state | pending: %{name: name, receiver: receiver, request: request}}
    {:ok, Enum.map(frames, &{:text, JSON.encode!(&1)}), state}
  end

  def acknowledge(%__MODULE__{pending: %{name: name} = pending} = state, name) do
    reply(pending, :ok)
    %{state | pending: nil}
  end

  def acknowledge(%__MODULE__{} = state, _name), do: state

  defp envelope(:twilio, stream, event), do: %{"event" => event, "streamSid" => stream}
  defp envelope(:telnyx, _stream, event), do: %{"event" => event}

  defp reply(pending, result),
    do: send(pending.receiver, {:vxpipe_playback_ack, pending.request, result})
end
