defmodule Vxpipe.Gateway.WebRTC.ConnectionSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias ExWebRTC.SessionDescription
  alias Vxpipe.Gateway.{Id, Session}
  alias Vxpipe.Gateway.WebRTC.{Connection, ConnectionIncarnationSupervisor}

  def start_link(_options) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  def accept_offer(session_id, %SessionDescription{} = offer, options) do
    with {:ok, session} <- Session.claim(session_id),
         {:ok, connection_id, incarnation} <- start_connection(session, options),
         {:ok, answer} <- negotiate(connection_id, incarnation, offer) do
      {:ok, connection_id, answer}
    end
  end

  def add_ice_candidates(connection_id, candidates) do
    Connection.add_ice_candidates(connection_id, candidates)
  end

  defp start_connection(session, options) do
    connection_id = Id.generate(:connection)

    child_options = [
      connection_id: connection_id,
      session: session,
      ice_servers: Keyword.get(options, :ice_servers, []),
      audio_jitter_latency_ms: Keyword.get(options, :audio_jitter_latency_ms, 200),
      candidate_gathering_timeout_ms:
        Keyword.get(options, :candidate_gathering_timeout_ms, 1_000),
      maximum_audio_packets: Keyword.get(options, :maximum_audio_packets, 500)
    ]

    case DynamicSupervisor.start_child(
           __MODULE__,
           {ConnectionIncarnationSupervisor, child_options}
         ) do
      {:ok, incarnation} -> {:ok, connection_id, incarnation}
      {:error, _reason} -> {:error, :connection_start_failed}
    end
  end

  defp negotiate(connection_id, incarnation, offer) do
    case safe_negotiate(connection_id, offer) do
      {:ok, answer} ->
        {:ok, answer}

      {:error, _reason} ->
        :ok = DynamicSupervisor.terminate_child(__MODULE__, incarnation)
        {:error, :connection_start_failed}
    end
  end

  defp safe_negotiate(connection_id, offer) do
    Connection.negotiate(connection_id, offer)
  catch
    :exit, _reason -> {:error, :connection_stopped}
  end
end
