defmodule Vxpipe.CallEngine.TranscriptRouter do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.TranscriptRouter.{Decision, PolicyPreparation, Projection}

  @call_timeout 1_000

  def start_link(options) do
    name = if Keyword.get(options, :register, true), do: via(options), else: nil
    GenServer.start_link(__MODULE__, options, name: name)
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :incarnation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec whereis(String.t()) :: pid() | nil
  def whereis(incarnation_id) when is_binary(incarnation_id) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, registry_key(incarnation_id)) do
      [{server, _value}] -> server
      [] -> nil
    end
  end

  @spec project(GenServer.server(), Projection.t()) ::
          {:ok, Decision.t()} | {:error, term()}
  def project(server, %Projection{} = projection) do
    safe_call(server, {:project, projection})
  end

  @spec project_current(GenServer.server(), String.t(), MapSet.t(String.t())) ::
          {:ok, Decision.t()} | {:error, term()}
  def project_current(server, source_participant_id, recipient_participant_ids)
      when is_binary(source_participant_id) and
             is_struct(recipient_participant_ids, MapSet) do
    safe_call(
      server,
      {:project_current, source_participant_id, recipient_participant_ids}
    )
  end

  @spec stats(GenServer.server()) :: map() | {:error, :unavailable}
  def stats(server), do: safe_call(server, :stats)

  @impl Vxpipe.CallEngine.Readiness.Adapter
  def readiness(server), do: safe_call(server, :readiness)

  @impl Vxpipe.CallEngine.Readiness.Adapter
  def readiness_binding(%{instance: router, binding: {_id, :prepared_policy, token}}),
    do: safe_call(router, {:prepared_policy_readiness, token})

  def readiness_binding(%{instance: router}), do: readiness(router)

  def prepare_policy(router, candidate, options),
    do: PolicyPreparation.request(router, candidate, options)

  def discard_policy(router, token), do: safe_call(router, {:discard_policy, token})

  @impl true
  def init(options) do
    with {:ok, identity} <- identity(options),
         {:ok, maximum_retained_revisions} <- positive(options, :maximum_retained_revisions) do
      {:ok,
       %{
         identity: identity,
         readiness_resource: Resource.new(:transcript_router, :room, __MODULE__, options),
         current: nil,
         pending_policy: nil,
         maximum_retained_revisions: maximum_retained_revisions,
         snapshots: %{}
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:readiness, _from, %{current: nil} = state) do
    {:reply, {:ok, state.readiness_resource, :preparing}, state}
  end

  def handle_call(:readiness, _from, state) do
    resource = PolicyPreparation.resource(state, state.current)

    {:reply, {:ok, resource, :ready}, state}
  end

  def handle_call({:prepare_policy, candidate, options}, _from, state) do
    case PolicyPreparation.begin(state, candidate, options) do
      {:ok, prepared, state} -> {:reply, {:ok, prepared}, state}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:prepared_policy_readiness, token}, _from, state),
    do: {:reply, PolicyPreparation.readiness(state, token), state}

  def handle_call({:discard_policy, token}, _from, state) do
    case PolicyPreparation.discard(state, token) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:vxpipe_apply_media_policy, snapshot}, _from, state) do
    with {:ok, snapshot} <- Snapshot.prepare(snapshot, state.current),
         {:ok, state} <- PolicyPreparation.install(state, snapshot) do
      snapshots =
        state.snapshots
        |> Map.put(snapshot.revision, snapshot)
        |> retain_latest(state.maximum_retained_revisions, snapshot)

      {:reply, :ok, %{state | current: snapshot, snapshots: snapshots}}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:project, projection}, _from, state) do
    {:reply, decide(projection, state), state}
  end

  def handle_call(
        {:project_current, source_participant_id, recipient_participant_ids},
        _from,
        %{current: %Snapshot{} = current} = state
      ) do
    projection = %Projection{
      tenant_id: state.identity.tenant_id,
      room_id: state.identity.room_id,
      incarnation_id: state.identity.incarnation_id,
      source_participant_id: source_participant_id,
      policy_revision: Snapshot.interval(current, :speech_to_text, source_participant_id),
      recipient_participant_ids: recipient_participant_ids
    }

    {:reply, decide(projection, state), state}
  end

  def handle_call({:project_current, _source, _recipients}, _from, state) do
    {:reply, {:error, :policy_unavailable}, state}
  end

  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       policy_revision: if(state.current, do: state.current.revision, else: nil),
       retained_policy_revisions: map_size(state.snapshots)
     }, state}
  end

  @impl true
  def handle_info(
        {:transcript_policy_expired, token},
        %{pending_policy: %{token: token}} = state
      ),
      do: {:noreply, PolicyPreparation.fail(state)}

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{pending_policy: %{monitor: monitor}} = state
      ),
      do: {:noreply, PolicyPreparation.fail(state)}

  def handle_info(_message, state), do: {:noreply, state}

  defp decide(_projection, %{current: nil}), do: {:error, :policy_unavailable}

  defp decide(%Projection{} = projection, state) do
    with :ok <- validate_projection(projection, state.identity),
         {:ok, source_snapshot} <- fetch_snapshot(state.snapshots, projection.policy_revision),
         :ok <- present_source(source_snapshot, projection.source_participant_id) do
      recipients = live_recipients(projection, state.current)

      {:ok,
       %Decision{
         recipient_participant_ids: recipients,
         source_policy: %{
           "media_policy_revision" => source_snapshot.revision,
           "save_transcripts" => source_snapshot.effective.save_transcripts
         }
       }}
    end
  end

  defp live_recipients(%Projection{} = projection, %Snapshot{} = current) do
    if projection.policy_revision ==
         Snapshot.interval(current, :speech_to_text, projection.source_participant_id) do
      permitted_recipients(projection, current)
    else
      MapSet.new()
    end
  end

  defp permitted_recipients(projection, current) do
    Enum.reduce(projection.recipient_participant_ids, MapSet.new(), fn recipient_id, allowed ->
      if MapSet.member?(current.present_participant_ids, recipient_id) and
           Effective.transcript_route_permitted?(
             current.effective,
             projection.source_participant_id,
             recipient_id
           ) do
        MapSet.put(allowed, recipient_id)
      else
        allowed
      end
    end)
  end

  defp validate_projection(projection, identity) do
    cond do
      projection.tenant_id != identity.tenant_id or projection.room_id != identity.room_id or
          projection.incarnation_id != identity.incarnation_id ->
        {:error, :wrong_room}

      not is_binary(projection.source_participant_id) or
        not is_integer(projection.policy_revision) or projection.policy_revision < 0 or
        not is_struct(projection.recipient_participant_ids, MapSet) or
          not Enum.all?(projection.recipient_participant_ids, &is_binary/1) ->
        {:error, :invalid_projection}

      true ->
        :ok
    end
  end

  defp fetch_snapshot(snapshots, revision) do
    case Map.fetch(snapshots, revision) do
      {:ok, snapshot} -> {:ok, snapshot}
      :error -> {:error, :unknown_policy_revision}
    end
  end

  defp present_source(snapshot, source_participant_id) do
    if MapSet.member?(snapshot.present_participant_ids, source_participant_id),
      do: :ok,
      else: {:error, :source_not_present}
  end

  defp identity(options) do
    with {:ok, tenant_id} <- nonempty(options, :tenant_id),
         {:ok, room_id} <- nonempty(options, :room_id),
         {:ok, incarnation_id} <- nonempty(options, :incarnation_id) do
      {:ok, %{tenant_id: tenant_id, room_id: room_id, incarnation_id: incarnation_id}}
    end
  end

  defp positive(options, key) do
    case Keyword.get(options, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _invalid -> {:error, {:invalid_transcript_router_option, key}}
    end
  end

  defp retain_latest(snapshots, maximum, current) do
    active_revisions =
      Enum.map(current.present_participant_ids, &Snapshot.interval(current, :speech_to_text, &1))

    retained_revisions =
      snapshots
      |> Map.keys()
      |> Enum.sort(:desc)
      |> Enum.take(maximum)

    Map.take(snapshots, retained_revisions ++ active_revisions)
  end

  defp nonempty(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) ->
        if String.trim(value) == "",
          do: {:error, {:invalid_transcript_router_option, key}},
          else: {:ok, value}

      _invalid ->
        {:error, {:invalid_transcript_router_option, key}}
    end
  end

  defp safe_call(server, message) do
    try do
      GenServer.call(server, message, @call_timeout)
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  defp via(options) do
    options
    |> Keyword.fetch!(:incarnation_id)
    |> registry_key()
    |> then(&{:via, Registry, {Vxpipe.CallEngine.RoomRegistry, &1}})
  end

  defp registry_key(incarnation_id), do: {:transcript_router, incarnation_id}
end
