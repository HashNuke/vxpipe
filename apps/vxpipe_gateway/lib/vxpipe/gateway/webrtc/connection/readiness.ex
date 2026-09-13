defmodule Vxpipe.Gateway.WebRTC.Connection.Readiness do
  @moduledoc false

  alias ExWebRTC.PeerConnection
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.Gateway.WebRTC.NegotiatedAudio

  def readiness(connection, direction) do
    with {:ok, binding, transport, profiles} <- observe(connection) do
      report(binding, direction, transport, Map.fetch!(profiles, direction))
    end
  end

  def resources(connection, options) do
    directions = if Keyword.get(options, :input?, false), do: [:output, :input], else: [:output]

    with {:ok, binding, transport, profiles} <- observe(connection) do
      resources =
        Enum.map(directions, fn direction ->
          {:ok, resource, _status} =
            report(binding, direction, transport, Map.fetch!(profiles, direction))

          resource
        end)

      {:ok, resources}
    end
  end

  def input_track(connection) do
    with {:ok, _binding, :connected, %{input: {:ready, media}}} <- observe(connection),
         do: {:ok, media.track},
         else: (_preparing_or_failed -> {:error, :unavailable})
  end

  def binding(state) do
    %{
      resource: state.media_readiness_resource,
      peer: state.peer_connection,
      output_track: state.output_track_id,
      negotiation_revision: state.negotiation_revision
    }
  end

  defp observe(connection) do
    connection = server(connection)

    with {:ok, binding} <- GenServer.call(connection, :media_readiness_binding, 1_000) do
      transceivers = PeerConnection.get_transceivers(binding.peer)
      transport = PeerConnection.get_connection_state(binding.peer)

      profiles =
        Map.new(
          [:output, :input],
          &{&1, NegotiatedAudio.resolve(&1, transceivers, binding.output_track)}
        )

      case GenServer.call(connection, :media_readiness_binding, 1_000) do
        {:ok, ^binding} -> {:ok, binding, transport, profiles}
        _changed -> {:error, :unavailable}
      end
    end
  rescue
    _exception -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp report(binding, direction, transport, {status, media}) do
    configuration = if media, do: media.configuration

    resource = %{
      binding.resource
      | kind: kind(direction),
        configuration:
          Resource.signature({binding.resource.configuration, direction, configuration})
    }

    {:ok, resource, status(transport, status)}
  end

  defp status(transport, _status) when transport in [:closed, :failed], do: :failed
  defp status(_transport, :failed), do: :failed
  defp status(:connected, status), do: status
  defp status(_transport, _status), do: :preparing

  defp kind(:output), do: :media_connection
  defp kind(:input), do: :media_input

  defp server(pid) when is_pid(pid), do: pid

  defp server(connection_id) when is_binary(connection_id),
    do: {:via, Registry, {Vxpipe.Gateway.WebRTC.Registry, {:connection, connection_id}}}
end
