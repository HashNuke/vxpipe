defmodule Vxpipe.Gateway.Telephony.MediaSession.Readiness do
  @moduledoc false

  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.Gateway.Telephony.SocketReadiness

  def readiness(session, direction) do
    with {:ok, binding, socket, status} <- observe(session),
         do: {:ok, resource(binding, socket, direction), status}
  end

  def resources(session, options) do
    directions = if Keyword.get(options, :input?, false), do: [:output, :input], else: [:output]

    with {:ok, binding, socket, _status} <- observe(session) do
      resources = Enum.map(directions, &resource(binding, socket, &1))
      dependencies = if socket, do: [socket.resource], else: []
      {:ok, resources ++ dependencies}
    end
  end

  def input_track(session) do
    with {:ok, _binding, %{input_track: track}, :ready} <- observe(session),
         do: {:ok, track},
         else: (_unavailable -> {:error, :unavailable})
  end

  def binding(state) do
    %{
      resource: state.readiness_resource,
      provider: state.binding.provider,
      socket_owner: state.socket_owner,
      stream_id: state.stream_id,
      identity: %{
        tenant_id: state.binding.tenant_id,
        room_id: state.binding.room_id,
        incarnation_id: state.binding.incarnation_id,
        participant_id: state.binding.participant_id,
        connection_id: state.connection_id
      }
    }
  end

  defp observe(session) do
    session = server(session)

    with {:ok, binding} <- GenServer.call(session, :readiness_binding, 1_000),
         {:ok, socket} <- SocketReadiness.snapshot(binding.socket_owner),
         {:ok, ^binding} <- GenServer.call(session, :readiness_binding, 1_000) do
      if valid_socket?(socket, binding),
        do: {:ok, binding, socket, socket.status},
        else: {:ok, binding, nil, :failed}
    else
      _unavailable_or_changed -> {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp valid_socket?(
         %{
           resource: %Resource{kind: :phone_transport} = resource,
           status: status,
           identity: identity,
           stream_id: stream,
           provider: provider,
           input_track: %{track_id: track}
         } = _socket,
         binding
       )
       when status in [:preparing, :ready, :failed] do
    Resource.bound?(resource) and resource.instance == binding.socket_owner and
      resource.adapter == SocketReadiness and resource.scope == binding.resource.scope and
      resource.binding == binding.resource.binding and identity == binding.identity and
      provider == binding.provider and stream == binding.stream_id and track == stream
  end

  defp valid_socket?(_socket, _binding), do: false

  defp resource(binding, socket, direction) do
    configuration = if socket, do: {socket.resource, socket.input_track}

    %{
      binding.resource
      | kind: if(direction == :output, do: :media_connection, else: :media_input),
        configuration:
          Resource.signature({binding.resource.configuration, direction, configuration})
    }
  end

  defp server(pid) when is_pid(pid), do: pid

  defp server(connection_id) when is_binary(connection_id),
    do:
      {:via, Registry, {Vxpipe.Gateway.Media.Registry, {:telephony_media_session, connection_id}}}
end
