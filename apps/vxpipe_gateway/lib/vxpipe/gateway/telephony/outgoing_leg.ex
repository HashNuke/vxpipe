defmodule Vxpipe.Gateway.Telephony.OutgoingLeg do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Telephony.{Event, Submission}

  alias Vxpipe.Gateway.Telephony.{
    MediaAdmission,
    MediaBinding,
    MediaSupervisor,
    OutgoingLegDialer,
    OutgoingLegIdentity,
    OutgoingLegLifecycle
  }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    leg_id = Keyword.fetch!(options, :leg_id)
    GenServer.start_link(__MODULE__, options, name: via(leg_id))
  end

  def child_spec(options) do
    leg_id = Keyword.fetch!(options, :leg_id)

    %{
      id: {__MODULE__, leg_id},
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

  @spec disconnect(pid(), timeout()) :: :ok | {:error, :telephony_leg_unavailable}
  def disconnect(leg, timeout) when is_pid(leg) do
    GenServer.call(leg, :disconnect, timeout)
  catch
    :exit, _reason -> {:error, :telephony_leg_unavailable}
  end

  @impl true
  def init(options) do
    {:ok,
     %{
       leg_id: Keyword.fetch!(options, :leg_id),
       request: Keyword.fetch!(options, :request),
       service: Keyword.fetch!(options, :service),
       media_admission: Keyword.fetch!(options, :media_admission),
       media_supervisor: Keyword.get(options, :media_supervisor, MediaSupervisor),
       binding: nil,
       result: nil,
       status: :starting,
       waiters: []
     }, {:continue, :dial}}
  end

  @impl true
  def handle_continue(:dial, state) do
    case OutgoingLegDialer.dial(
           state.leg_id,
           state.request,
           state.service,
           state.media_admission,
           self()
         ) do
      {:ok, %Submission{status: :unknown}} ->
        {:noreply, succeed(state, :unknown, nil)}

      {:ok, %Submission{status: :accepted} = submission} ->
        case adopt_submission(state, submission) do
          {:ok, binding} -> {:noreply, succeed(state, :accepted, binding)}
          {:error, reason} -> {:noreply, fail(state, reason)}
        end

      {:error, reason} ->
        {:noreply, fail(state, reason)}
    end
  end

  @impl true
  def handle_call(:await, _from, %{result: result} = state) when not is_nil(result) do
    {:reply, result, state}
  end

  def handle_call(:await, from, state) do
    {:noreply, %{state | waiters: [from | state.waiters]}}
  end

  def handle_call(
        :disconnect,
        _from,
        %{binding: %MediaBinding{} = binding, status: :accepted} = state
      ) do
    :ok =
      OutgoingLegLifecycle.end_attempt(
        binding,
        state.service,
        state.leg_id,
        :transfer_cancelled
      )

    {:stop, :normal, :ok, state}
  end

  def handle_call(:disconnect, _from, state), do: {:stop, :normal, :ok, state}

  def handle_call(
        {:event, %Event{kind: kind} = event},
        _from,
        %{status: :unknown} = state
      )
      when kind in [:outgoing, :answered, :ended] do
    case OutgoingLegIdentity.from_event(
           event,
           state.leg_id,
           state.request,
           state.service,
           self()
         ) do
      {:ok, binding} ->
        case register_and_bind(state, binding) do
          :ok -> handle_adopted_event(event, binding, state)
          {:error, reason} -> {:reply, {:error, reason}, fail(state, reason)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:event, %Event{kind: :outgoing} = event},
        _from,
        %{status: :accepted} = state
      ) do
    case OutgoingLegIdentity.from_event(
           event,
           state.leg_id,
           state.request,
           state.service,
           self()
         ) do
      {:ok, binding} when binding == state.binding -> {:reply, :ok, state}
      _mismatch -> {:reply, {:error, :telephony_leg_mismatch}, state}
    end
  end

  def handle_call(
        {:event, %Event{kind: :media_started, stream_id: stream_id} = event},
        {source, _tag},
        %{binding: %MediaBinding{} = binding, status: :accepted} = state
      ) do
    result =
      with true <- MediaBinding.matches_event?(binding, event),
           {:ok, _connection} <-
             MediaSupervisor.start_outbound_session(
               state.media_supervisor,
               state.request,
               binding,
               source,
               stream_id
             ),
           :ok <-
             MediaSupervisor.report_transfer_control(
               binding.client_state_leg_id,
               source,
               :media_ready
             ) do
        :ok
      else
        false -> {:error, :telephony_leg_mismatch}
        {:error, reason} -> {:error, reason}
      end

    {:reply, result, state}
  end

  def handle_call(
        {:event, %Event{kind: :media} = event},
        {source, _tag},
        %{binding: %MediaBinding{} = binding, status: :accepted} = state
      ) do
    result =
      if MediaBinding.matches_event?(binding, event) do
        MediaSupervisor.handle_event(binding.client_state_leg_id, source, event)
      else
        {:error, :telephony_leg_mismatch}
      end

    {:reply, result, state}
  end

  def handle_call(
        {:event, %Event{kind: :dtmf, digit: "1"} = event},
        {source, _tag},
        %{binding: %MediaBinding{} = binding, status: :accepted} = state
      ) do
    result =
      if MediaBinding.matches_event?(binding, event) do
        MediaSupervisor.report_transfer_control(binding.client_state_leg_id, source, :accept)
      else
        {:error, :telephony_leg_mismatch}
      end

    {:reply, result, state}
  end

  def handle_call(
        {:event, %Event{kind: :dtmf} = event},
        _from,
        %{binding: %MediaBinding{} = binding, status: :accepted} = state
      ) do
    result =
      if MediaBinding.matches_event?(binding, event),
        do: :ok,
        else: {:error, :telephony_leg_mismatch}

    {:reply, result, state}
  end

  def handle_call(
        {:event, %Event{kind: kind} = event},
        _from,
        %{binding: %MediaBinding{} = binding, status: :accepted} = state
      )
      when kind in [:answered, :answering_machine, :ended] do
    case OutgoingLegLifecycle.handle(event, binding, state.service, state.leg_id) do
      {:keep, result} -> {:reply, result, state}
      {:stop, result} -> {:stop, :normal, result, state}
    end
  end

  def handle_call({:event, _event}, _from, state) do
    {:reply, {:error, :telephony_event_not_supported}, state}
  end

  @impl true
  def handle_info(:retire, %{status: :failed} = state), do: {:stop, :normal, state}
  def handle_info(:retire, state), do: {:noreply, state}

  defp reply_waiters(waiters, result), do: Enum.each(waiters, &GenServer.reply(&1, result))

  defp succeed(state, status, binding) do
    reply_waiters(state.waiters, :ok)
    %{state | binding: binding, result: :ok, status: status, waiters: []}
  end

  defp fail(state, reason) do
    result = {:error, reason}
    :ok = MediaAdmission.revoke(state.media_admission, self())
    reply_waiters(state.waiters, result)
    Process.send_after(self(), :retire, 1_000)
    %{state | result: result, status: :failed, waiters: []}
  end

  defp adopt_submission(state, submission) do
    with {:ok, binding} <-
           OutgoingLegIdentity.from_submission(
             submission,
             state.leg_id,
             state.request,
             state.service,
             self()
           ),
         :ok <- register_and_bind(state, binding) do
      {:ok, binding}
    end
  end

  defp register_and_bind(state, %MediaBinding{} = binding) do
    key = {binding.provider, binding.service_id, binding.provider_call_leg_id}

    case Registry.register(Vxpipe.Gateway.Telephony.LegRegistry, key, :outgoing) do
      {:ok, _owner} ->
        bind_registered(state, key, binding)

      {:error, {:already_registered, _owner}} ->
        {:error, :telephony_leg_already_owned}
    end
  end

  defp handle_adopted_event(%Event{kind: :outgoing}, binding, state) do
    {:reply, :ok, %{state | binding: binding, status: :accepted}}
  end

  defp handle_adopted_event(%Event{} = event, binding, state) do
    state = %{state | binding: binding, status: :accepted}

    case OutgoingLegLifecycle.handle(event, binding, state.service, state.leg_id) do
      {:keep, result} -> {:reply, result, state}
      {:stop, result} -> {:stop, :normal, result, state}
    end
  end

  defp bind_registered(state, key, binding) do
    case MediaAdmission.bind(state.media_admission, binding) do
      :ok ->
        :ok

      {:error, reason} ->
        Registry.unregister(Vxpipe.Gateway.Telephony.LegRegistry, key)
        {:error, reason}
    end
  end

  defp via(leg_id) do
    {:via, Registry, {Vxpipe.Gateway.Telephony.LegRegistry, {:outgoing, leg_id}}}
  end
end
