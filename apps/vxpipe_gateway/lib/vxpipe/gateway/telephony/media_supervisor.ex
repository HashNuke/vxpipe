defmodule Vxpipe.Gateway.Telephony.MediaSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Telephony.{Event, OutboundLegRequest}
  alias Vxpipe.Calls.TelephonyAdmissionClaim

  alias Vxpipe.Gateway.Telephony.{
    MediaBinding,
    MediaConnectionSupervisor,
    MediaPipelineSet,
    MediaSession
  }

  def start_link(options) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: Keyword.get(options, :name, __MODULE__))
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec start_session(
          DynamicSupervisor.supervisor(),
          TelephonyAdmissionClaim.t(),
          MediaBinding.t(),
          pid(),
          String.t()
        ) :: {:ok, pid()} | {:error, term()}
  def start_session(
        supervisor \\ __MODULE__,
        %TelephonyAdmissionClaim{} = claim,
        %MediaBinding{} = binding,
        socket_owner,
        stream_id
      )
      when is_pid(socket_owner) and is_binary(stream_id) do
    start_connection(
      supervisor,
      claim.call.plan.actor_id,
      binding,
      socket_owner,
      stream_id
    )
  end

  @spec start_outbound_session(
          DynamicSupervisor.supervisor(),
          OutboundLegRequest.t(),
          MediaBinding.t(),
          pid(),
          String.t()
        ) :: {:ok, pid()} | {:error, term()}
  def start_outbound_session(
        supervisor \\ __MODULE__,
        %OutboundLegRequest{} = request,
        %MediaBinding{} = binding,
        socket_owner,
        stream_id
      )
      when is_pid(socket_owner) and is_binary(stream_id) do
    start_connection(supervisor, request.actor_id, binding, socket_owner, stream_id)
  end

  @spec handle_event(String.t(), pid(), Event.t()) :: :ok | {:error, term()}
  def handle_event(connection_id, source, %Event{} = event)
      when is_binary(connection_id) and is_pid(source) do
    with {:ok, session} <- lookup(:telephony_media_session, connection_id) do
      MediaSession.handle_event(session, source, event)
    end
  end

  @spec report_transfer_control(String.t(), pid(), :accept | :media_ready) ::
          :ok | {:error, term()}
  def report_transfer_control(connection_id, source, action)
      when is_binary(connection_id) and is_pid(source) and action in [:accept, :media_ready] do
    with {:ok, session} <- lookup(:telephony_media_session, connection_id) do
      MediaSession.report_transfer_control(session, source, action)
    end
  end

  @spec snapshot(String.t()) :: {:ok, map()} | {:error, :media_session_not_found}
  def snapshot(connection_id) when is_binary(connection_id) do
    with {:ok, connection} <- lookup(:telephony_media_connection, connection_id),
         {:ok, session} <- lookup(:telephony_media_session, connection_id),
         {:ok, snapshot} <- MediaSession.snapshot(session) do
      {:ok, Map.put(snapshot, :connection, connection)}
    end
  end

  defp start_connection(supervisor, actor_id, binding, socket_owner, stream_id) do
    with {:ok, media_pipelines} <- MediaPipelineSet.resolve(binding.provider) do
      options = [
        actor_id: actor_id,
        connection_id: binding.client_state_leg_id,
        binding: binding,
        media_pipelines: media_pipelines,
        socket_owner: socket_owner,
        stream_id: stream_id
      ]

      case DynamicSupervisor.start_child(supervisor, {MediaConnectionSupervisor, options}) do
        {:ok, connection} -> {:ok, connection}
        {:error, {:already_started, connection}} -> {:ok, connection}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp lookup(kind, connection_id) do
    case Registry.lookup(Vxpipe.Gateway.Media.Registry, {kind, connection_id}) do
      [{process, _value}] -> {:ok, process}
      [] -> {:error, :media_session_not_found}
    end
  end
end
