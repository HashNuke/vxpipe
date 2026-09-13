defmodule Vxpipe.Gateway.Telephony.SocketReadiness do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.Gateway.Telephony.MediaBinding

  @formats %{
    telnyx: %{codec: :opus, sample_rate: 16_000, channels: 1},
    twilio: %{codec: :pcmu, sample_rate: 8_000, channels: 1}
  }

  def new(%MediaBinding{} = binding) do
    Resource.new(:phone_transport, {:participant, binding.participant_id}, __MODULE__, binding,
      binding: binding.client_state_leg_id
    )
  end

  @impl true
  def readiness(socket) do
    with {:ok, binding} <- snapshot(socket),
         do: {:ok, binding.resource, binding.status}
  end

  def snapshot(socket) when is_pid(socket) do
    receiver = :erlang.alias([:reply])
    reference = make_ref()
    monitor = Process.monitor(socket)

    try do
      send(socket, {:vxpipe_phone_readiness, receiver, reference})

      receive do
        {:vxpipe_phone_readiness_reply, ^reference, result} -> result
        {:DOWN, ^monitor, :process, ^socket, _reason} -> {:error, :unavailable}
      after
        1_000 -> {:error, :unavailable}
      end
    after
      :erlang.unalias(receiver)
      Process.demonitor(monitor, [:flush])
    end
  end

  def snapshot(_socket), do: {:error, :unavailable}

  def reply(state, receiver, reference) do
    send(receiver, {:vxpipe_phone_readiness_reply, reference, {:ok, projection(state)}})
    :ok
  end

  defp projection(state) do
    input_track = input_track(state.binding.provider, state.stream_id)

    resource = %{
      state.readiness_resource
      | configuration:
          Resource.signature(
            {state.readiness_resource.configuration, state.stream_id, input_track}
          )
    }

    status =
      cond do
        not MediaBinding.valid?(state.binding) -> :failed
        input_track == nil -> :preparing
        true -> :ready
      end

    %{
      resource: resource,
      status: status,
      provider: state.binding.provider,
      stream_id: state.stream_id,
      input_track: input_track,
      identity: %{
        tenant_id: state.binding.tenant_id,
        room_id: state.binding.room_id,
        incarnation_id: state.binding.incarnation_id,
        participant_id: state.binding.participant_id,
        connection_id: state.binding.client_state_leg_id
      }
    }
  end

  defp input_track(provider, stream_id) when is_binary(stream_id) and byte_size(stream_id) > 0 do
    case Map.fetch(@formats, provider) do
      {:ok, format} -> Map.put(format, :track_id, stream_id)
      :error -> nil
    end
  end

  defp input_track(_provider, _stream), do: nil
end
