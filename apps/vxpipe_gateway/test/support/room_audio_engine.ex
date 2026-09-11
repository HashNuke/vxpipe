defmodule Vxpipe.Gateway.TestRoomAudioEngine do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot

  def room_audio_configuration(%{configuration: configuration}), do: {:ok, configuration}

  def register_room_audio_enforcer(%{snapshot: %Snapshot{} = snapshot}, enforcer) do
    case GenServer.call(enforcer, {:vxpipe_apply_media_policy, snapshot}) do
      :ok -> {:ok, snapshot}
      {:error, reason} -> {:error, reason}
    end
  end

  def push_room_audio(%{observer: observer}, frame) do
    send(observer, {:test_room_audio, frame})
    :ok
  end
end
