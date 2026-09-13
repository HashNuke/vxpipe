defmodule Vxpipe.CallEngine.LiveInspection.Buffer do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Readiness.Resource

  alias Vxpipe.CallEngine.Archive.Fact
  alias Vxpipe.CallEngine.CallVariables.{BaselineSnapshot, UpdateSnapshot}
  alias Vxpipe.CallEngine.LiveInspection.{Port, Snapshot}

  @call_timeout 250

  @impl Vxpipe.CallEngine.Readiness.Adapter
  def readiness(buffer) do
    GenServer.call(buffer, :readiness, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def start_link(options) do
    identity = Keyword.fetch!(options, :identity)
    GenServer.start_link(__MODULE__, options, name: via(identity.tenant_id, identity.call_id))
  end

  def child_spec(options) do
    identity = Keyword.fetch!(options, :identity)

    %{
      id: {__MODULE__, identity.incarnation_id},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec port(GenServer.server()) :: {:ok, Port.t()} | {:error, :unavailable}
  def port(buffer) do
    {:ok, GenServer.call(buffer, :port, @call_timeout)}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec port(String.t(), String.t()) :: {:ok, Port.t()} | {:error, :unavailable}
  def port(tenant_id, call_id) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, registry_key(tenant_id, call_id)) do
      [{buffer, _value}] -> port(buffer)
      [] -> {:error, :unavailable}
    end
  end

  @spec snapshot(String.t(), String.t()) :: {:ok, Snapshot.t()} | {:error, :call_not_live}
  def snapshot(tenant_id, call_id) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, registry_key(tenant_id, call_id)) do
      [{buffer, _value}] -> {:ok, GenServer.call(buffer, :snapshot, @call_timeout)}
      [] -> {:error, :call_not_live}
    end
  catch
    :exit, _reason -> {:error, :call_not_live}
  end

  @impl true
  def init(options) do
    identity = Keyword.fetch!(options, :identity)
    maximum_pending_records = Keyword.fetch!(options, :maximum_pending_records)
    maximum_retained_records = Keyword.fetch!(options, :maximum_retained_records)
    port = Port.new(self(), maximum_pending_records)

    {:ok,
     %{
       identity: identity,
       readiness_resource: Resource.new(:live_inspection, :room, __MODULE__, options),
       port: port,
       maximum_retained_records: maximum_retained_records,
       records: :queue.new(),
       record_count: 0,
       dropped_records: 0,
       latest_fact_sequence: nil,
       latest_variable_revision: nil
     }}
  end

  @impl true
  def handle_call(:readiness, _from, state) do
    status = if Port.open?(state.port), do: :ready, else: :failed
    {:reply, {:ok, state.readiness_resource, status}, state}
  end

  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  def handle_call(:snapshot, _from, state) do
    port_stats = Port.stats(state.port)

    snapshot = %Snapshot{
      tenant_id: state.identity.tenant_id,
      call_id: state.identity.call_id,
      room_id: state.identity.room_id,
      incarnation_id: state.identity.incarnation_id,
      records: :queue.to_list(state.records),
      latest_fact_sequence: state.latest_fact_sequence,
      latest_variable_revision: state.latest_variable_revision,
      dropped_records: state.dropped_records,
      rejected_records: port_stats.rejected
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_info({:vxpipe_live_inspection, kind, token, record}, state) do
    case Port.message(state.port, {kind, token, record}) do
      {:ok, record} -> {:noreply, accept(record, state)}
      :error -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Port.close(state.port)
    :ok
  end

  defp accept(record, state) do
    if belongs_to_call?(record, state.identity) do
      :ok = Port.acknowledge(state.port)
      state |> retain(record) |> advance(record)
    else
      :ok = Port.discard(state.port)
      state
    end
  end

  defp retain(state, record) do
    records = :queue.in(record, state.records)
    count = state.record_count + 1

    if count > state.maximum_retained_records do
      {{:value, _oldest}, records} = :queue.out(records)
      %{state | records: records, dropped_records: state.dropped_records + 1}
    else
      %{state | records: records, record_count: count}
    end
  end

  defp advance(state, %Fact{} = fact) do
    %{state | latest_fact_sequence: max(state.latest_fact_sequence || 0, fact.sequence)}
  end

  defp advance(state, %BaselineSnapshot{} = snapshot) do
    %{
      state
      | latest_variable_revision:
          max(state.latest_variable_revision || 0, snapshot.global_revision)
    }
  end

  defp advance(state, %UpdateSnapshot{} = snapshot) do
    %{
      state
      | latest_variable_revision:
          max(state.latest_variable_revision || 0, snapshot.global_revision)
    }
  end

  defp belongs_to_call?(record, identity) do
    record.tenant_id == identity.tenant_id and record.call_id == identity.call_id and
      record.room_id == identity.room_id and record.incarnation_id == identity.incarnation_id
  end

  defp via(tenant_id, call_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, registry_key(tenant_id, call_id)}}
  end

  defp registry_key(tenant_id, call_id), do: {:live_inspection, tenant_id, call_id}
end
