defmodule Vxpipe.Gateway.Telephony.Leg do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot
  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Calls.TelephonyAdmissionClaim
  alias Vxpipe.Gateway.Telephony.{IncomingLegActivationResult, LegUsage}

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

  @spec await(pid(), timeout()) :: :ok | {:ok, term()} | {:error, term()}
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

  @doc false
  def dispatch_async(leg, %Event{} = event) when is_pid(leg),
    do: :gen_server.send_request(leg, {:event, event})

  @impl true
  def init(options) do
    state = %{
      activation: nil,
      backend: Keyword.fetch!(options, :backend),
      claim: nil,
      clock: Keyword.fetch!(options, :clock),
      identity: Keyword.fetch!(options, :identity),
      initial_event: Keyword.fetch!(options, :event),
      incarnation_id: nil,
      result: nil,
      status: :starting,
      usage: nil,
      waiters: []
    }

    {:ok, state, {:continue, :admit}}
  end

  @impl true
  def handle_continue(:admit, state) do
    {status, claim, activation, incarnation_id, result} = admit(state)
    Enum.each(state.waiters, &GenServer.reply(&1, result))

    state = %{
      state
      | activation: activation,
        claim: claim,
        incarnation_id: incarnation_id,
        result: result,
        status: status,
        usage: activation_usage(activation),
        waiters: []
    }

    if status in [:failed, :unclaimed] do
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

  def handle_call(
        {:event, %Event{kind: kind} = event},
        {source, _tag},
        %{status: :answering} = state
      )
      when kind in [:answered, :media_started] do
    with :ok <- matching_event(state.claim, event) do
      state = state |> observe_usage(event) |> project_started(event)

      case dispatch_start_event(state, source, event) do
        :ok -> {:reply, :ok, state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:event, %Event{kind: :answered} = event}, _from, %{status: :running} = state) do
    case matching_event(state.claim, event) do
      :ok -> {:reply, :ok, observe_usage(state, event)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:event, event}, {source, _tag}, %{status: :running} = state) do
    case matching_event(state.claim, event) do
      :ok ->
        state = observe_usage(state, event)

        case call_backend(state.backend, :handle_live_event, [
               state.claim,
               state.activation,
               source,
               event
             ]) do
          :ok -> {:reply, :ok, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:event, _event}, _from, state) do
    {:reply, {:error, :telephony_leg_unavailable}, state}
  end

  @impl true
  def handle_info(:retire, %{status: status} = state) when status in [:failed, :unclaimed],
    do: {:stop, :normal, state}

  def handle_info(:retire, state), do: {:noreply, state}

  defp admit(state) do
    case call_backend(state.backend, :claim_incoming, [state.identity, state.initial_event]) do
      {:ok, %TelephonyAdmissionClaim{} = claim} ->
        start_call(%{state | claim: claim})

      {:duplicate, %TelephonyAdmissionClaim{call: %{state: :running}} = claim} ->
        {:failed, claim, nil, claim.call.incarnation_id, :ok}

      {:duplicate, %TelephonyAdmissionClaim{call: %{state: :failed}} = claim} ->
        {:failed, claim, nil, nil, :ok}

      {:duplicate, %TelephonyAdmissionClaim{call: %{state: :admitting}} = claim} ->
        case call_backend(state.backend, :mark_incoming_failed, [claim, :startup_unknown]) do
          {:ok, failed} -> {:failed, failed, nil, nil, :ok}
          {:error, _reason} -> {:failed, claim, nil, nil, :ok}
        end

      {:error, reason} ->
        {:unclaimed, nil, nil, nil, {:error, reason}}

      _invalid ->
        {:unclaimed, nil, nil, nil, {:error, :invalid_telephony_call_backend_response}}
    end
  end

  defp start_call(state) do
    case call_backend(state.backend, :start_incoming, [state.claim]) do
      {:ok, %RoomSnapshot{} = room} ->
        activate_call(state, room)

      {:error, _reason} ->
        case call_backend(state.backend, :mark_incoming_failed, [
               state.claim,
               :room_start_failed
             ]) do
          {:ok, claim} -> {:failed, claim, nil, nil, :ok}
          _projection_outcome -> {:failed, state.claim, nil, nil, :ok}
        end

      _invalid ->
        {:unclaimed, nil, nil, nil, {:error, :invalid_telephony_call_backend_response}}
    end
  end

  defp activate_call(state, %RoomSnapshot{incarnation_id: incarnation_id} = room) do
    case call_backend(state.backend, :activate_incoming, [
           state.identity,
           state.claim,
           room,
           self()
         ]) do
      {:ok, activation} ->
        {:answering, state.claim, activation, incarnation_id, activation_result(activation)}

      {:error, _reason} ->
        case call_backend(state.backend, :mark_incoming_failed, [
               state.claim,
               :leg_activation_failed
             ]) do
          {:ok, claim} -> {:failed, claim, nil, nil, :ok}
          _projection_outcome -> {:failed, state.claim, nil, nil, :ok}
        end

      _invalid ->
        {:unclaimed, nil, nil, nil, {:error, :invalid_telephony_call_backend_response}}
    end
  end

  defp project_started(state, event) do
    started_at = start_time(event, state.clock)

    claim =
      case call_backend(state.backend, :mark_incoming_started, [
             state.claim,
             state.incarnation_id,
             started_at
           ]) do
        {:ok, claim} -> claim
        _projection_outcome -> state.claim
      end

    %{state | claim: claim, status: :running}
  end

  defp activation_result(%IncomingLegActivationResult{media_url: media_url}),
    do: {:ok, media_url}

  defp activation_result(_custom_activation), do: :ok

  defp activation_usage(%IncomingLegActivationResult{usage: usage}), do: usage
  defp activation_usage(_custom_activation), do: nil

  defp observe_usage(state, event) do
    %{state | usage: LegUsage.observe(state.usage, event)}
  end

  defp start_time(%Event{occurred_at: %DateTime{} = occurred_at}, _clock), do: occurred_at
  defp start_time(%Event{kind: :media_started}, clock), do: clock.()

  defp dispatch_start_event(_state, _source, %Event{kind: :answered}), do: :ok

  defp dispatch_start_event(state, source, %Event{kind: :media_started} = event) do
    call_backend(state.backend, :handle_live_event, [state.claim, state.activation, source, event])
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
