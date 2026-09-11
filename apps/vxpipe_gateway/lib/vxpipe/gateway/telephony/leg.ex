defmodule Vxpipe.Gateway.Telephony.Leg do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot
  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Calls.TelephonyAdmissionClaim

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    identity = Keyword.fetch!(options, :identity)
    event = Keyword.fetch!(options, :event)
    GenServer.start_link(__MODULE__, options, name: via(identity, event))
  end

  def child_spec(options) do
    identity = Keyword.fetch!(options, :identity)
    event = Keyword.fetch!(options, :event)

    %{
      id: {__MODULE__, key(identity, event)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec await(pid(), timeout()) :: :ok | {:error, term()}
  def await(leg, timeout) when is_pid(leg) do
    GenServer.call(leg, :await, timeout)
  catch
    :exit, _reason -> {:error, :telephony_leg_unavailable}
  end

  @spec dispatch(pid(), Event.t(), timeout()) :: :ok | {:error, term()}
  def dispatch(leg, %Event{} = event, timeout) when is_pid(leg) do
    GenServer.call(leg, {:event, event}, timeout)
  catch
    :exit, _reason -> {:error, :telephony_leg_unavailable}
  end

  @impl true
  def init(options) do
    state = %{
      backend: Keyword.fetch!(options, :backend),
      claim: nil,
      clock: Keyword.fetch!(options, :clock),
      identity: Keyword.fetch!(options, :identity),
      initial_event: Keyword.fetch!(options, :event),
      result: nil,
      status: :starting,
      waiters: []
    }

    {:ok, state, {:continue, :admit}}
  end

  @impl true
  def handle_continue(:admit, state) do
    {status, claim, result} = admit(state)
    Enum.each(state.waiters, &GenServer.reply(&1, result))
    state = %{state | claim: claim, result: result, status: status, waiters: []}

    if status == :unclaimed do
      Process.send_after(self(), :retire, 1_000)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:await, _from, %{result: result} = state) when not is_nil(result) do
    {:reply, result, state}
  end

  def handle_call(:await, from, state) do
    {:noreply, %{state | waiters: [from | state.waiters]}}
  end

  def handle_call({:event, event}, _from, %{status: :running} = state) do
    with :ok <- matching_event(state.claim, event),
         :ok <- call_backend(state.backend, :handle_live_event, [state.claim, event]) do
      {:reply, :ok, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:event, _event}, _from, state) do
    {:reply, {:error, :telephony_leg_unavailable}, state}
  end

  @impl true
  def handle_info(:retire, %{status: :unclaimed} = state), do: {:stop, :normal, state}
  def handle_info(:retire, state), do: {:noreply, state}

  defp admit(state) do
    case call_backend(state.backend, :claim_incoming, [state.identity, state.initial_event]) do
      {:ok, %TelephonyAdmissionClaim{} = claim} ->
        start_call(%{state | claim: claim})

      {:duplicate, %TelephonyAdmissionClaim{call: %{state: :running}} = claim} ->
        {:running, claim, :ok}

      {:duplicate, %TelephonyAdmissionClaim{call: %{state: :failed}} = claim} ->
        {:failed, claim, :ok}

      {:duplicate, %TelephonyAdmissionClaim{call: %{state: :admitting}} = claim} ->
        case call_backend(state.backend, :mark_incoming_failed, [claim, :startup_unknown]) do
          {:ok, failed} -> {:failed, failed, :ok}
          {:error, _reason} -> {:failed, claim, :ok}
        end

      {:error, reason} ->
        {:unclaimed, nil, {:error, reason}}

      _invalid ->
        {:unclaimed, nil, {:error, :invalid_telephony_call_backend_response}}
    end
  end

  defp start_call(state) do
    case call_backend(state.backend, :start_incoming, [state.claim]) do
      {:ok, %RoomSnapshot{incarnation_id: incarnation_id}} ->
        started_at = state.clock.()

        case call_backend(state.backend, :mark_incoming_started, [
               state.claim,
               incarnation_id,
               started_at
             ]) do
          {:ok, claim} -> {:running, claim, :ok}
          _projection_outcome -> {:running, state.claim, :ok}
        end

      {:error, _reason} ->
        case call_backend(state.backend, :mark_incoming_failed, [
               state.claim,
               :room_start_failed
             ]) do
          {:ok, claim} -> {:failed, claim, :ok}
          _projection_outcome -> {:failed, state.claim, :ok}
        end

      _invalid ->
        {:unclaimed, nil, {:error, :invalid_telephony_call_backend_response}}
    end
  end

  defp matching_event(claim, event) do
    if event.provider == claim.provider and
         event.provider_connection_id == claim.provider_connection_id and
         event.provider_call_control_id == claim.provider_call_control_id and
         event.provider_call_leg_id == claim.provider_call_leg_id and
         event.provider_call_session_id == claim.provider_call_session_id,
       do: :ok,
       else: {:error, :telephony_leg_mismatch}
  end

  defp call_backend({module, context}, function, arguments) do
    apply(module, function, [context | arguments])
  rescue
    _exception -> {:error, :telephony_call_backend_failed}
  catch
    _kind, _reason -> {:error, :telephony_call_backend_failed}
  end

  defp via(identity, event) do
    {:via, Registry, {Vxpipe.Gateway.Telephony.LegRegistry, key(identity, event)}}
  end

  defp key(identity, event), do: {event.provider, identity.service_id, event.provider_call_leg_id}
end
