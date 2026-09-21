defmodule Vxpipe.Providers.Google.STTSession do
  @moduledoc false

  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STTProvider

  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, SessionTree, STTProvider}
  alias Vxpipe.Providers.Google.{STT, STTSocket}

  @setup_timeout 15_000
  @renew_after 420_000
  @expire_after 570_000
  @renew_retry 10_000
  @maximum_pending_turns 8

  @derive {Inspect, only: [:ready?]}
  defstruct [
    :channel,
    :socket_supervisor,
    :config,
    :wire,
    :wire_monitor,
    :wire_module,
    :wire_options,
    :setup_timer,
    :pending_wire,
    :pending_monitor,
    :pending_timer,
    :renew_timer,
    :expire_timer,
    ready?: false,
    pending_ready?: false,
    active: nil,
    pending: []
  ]

  @impl true
  def configure(options) do
    with {:ok, public} <- STT.public_options(options) do
      Descriptor.new(
        kind: :stt,
        settings: public,
        format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: 16_000,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        usage_identity: %{
          provider: :google,
          model: public.model,
          provenance: :provider_reported
        },
        readiness: :provider_acknowledged,
        endpointing: :provider_semantic,
        speech_start?: true
      )
    end
  end

  @impl true
  def start_link(options), do: STTProvider.start_link(__MODULE__, options)

  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:push_audio, audio}, 5_000)

  @impl true
  def close(pid) do
    GenServer.call(pid, :close, 5_000)
  catch
    :exit, {:noproc, _call} -> :ok
    :exit, {:normal, _call} -> :ok
  end

  @impl true
  def init(options) do
    allocation = Keyword.fetch!(options, :allocation)
    descriptor = Keyword.fetch!(options, :descriptor)
    channel = options |> Keyword.fetch!(:channel) |> GenServer.whereis()
    private = Keyword.fetch!(options, :private)
    config = Keyword.fetch!(private, :config)
    wire_module = Keyword.get(private, :wire_module, STTSocket)
    wire_options = Keyword.get(private, :wire_options, [])

    with %STT{} <- config,
         {:ok, expected} <-
           configure(
             model: config.model,
             encoding: config.encoding,
             sample_rate: config.sample_rate
           ),
         true <- descriptor == expected,
         true <- is_atom(wire_module) and is_list(wire_options) and Keyword.keyword?(wire_options),
         :ok <- Channel.bind(channel) do
      {:ok,
       %__MODULE__{
         channel: channel,
         socket_supervisor: SessionTree.providers(allocation),
         config: config,
         wire_module: wire_module,
         wire_options: wire_options
       }, {:continue, :connect}}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_continue(:connect, state) do
    with {:ok, wire} <- start_socket(state, []),
         :ok <- state.wire_module.send_control(wire, JSON.encode!(STT.setup(state.config))) do
      timer = Process.send_after(self(), :setup_timeout, @setup_timeout)
      {:noreply, %{state | wire: wire, wire_monitor: Process.monitor(wire), setup_timer: timer}}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, state}
    end
  end

  @impl true
  def handle_call({:push_audio, audio}, _from, %{ready?: true} = state) do
    with {:ok, _encoded} <- STT.encode_audio(audio),
         :ok <- state.wire_module.send_audio(state.wire, audio) do
      {:reply, :ok, state}
    else
      {:error, :invalid_audio} -> {:reply, {:error, :session_failed}, state}
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:push_audio, _audio}, _from, state),
    do: {:reply, {:error, :session_failed}, state}

  def handle_call(:close, _from, state) do
    if state.wire, do: state.wire_module.close(state.wire)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:vxpipe_stt_transport, wire, {:message, payload}}, %{wire: wire} = state) do
    with {:ok, events} <- STT.decode(payload),
         {:ok, state} <- Enum.reduce_while(events, {:ok, state}, &reduce_event/2) do
      {:noreply, maybe_swap(state)}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info(
        {:vxpipe_stt_transport, wire, {:message, payload}},
        %{pending_wire: wire} = state
      ) do
    case STT.decode(payload) do
      {:ok, events} ->
        if Enum.member?(events, :ready) do
          if state.pending_timer, do: Process.cancel_timer(state.pending_timer)
          {:noreply, maybe_swap(%{state | pending_ready?: true, pending_timer: nil})}
        else
          {:noreply, state}
        end

      _invalid ->
        {:noreply, discard_pending(state)}
    end
  end

  def handle_info({:vxpipe_socket_connected, wire}, %{pending_wire: wire} = state) do
    case state.wire_module.send_control(wire, JSON.encode!(STT.setup(state.config))) do
      :ok ->
        timer = Process.send_after(self(), {:pending_timeout, wire}, @setup_timeout)
        {:noreply, %{state | pending_timer: timer}}

      _failure ->
        {:noreply, discard_pending(state)}
    end
  end

  def handle_info(
        {:vxpipe_stt_transport, wire, {:closed, _reason}},
        %{pending_wire: wire} = state
      ),
      do: {:noreply, discard_pending(state)}

  def handle_info({:vxpipe_stt_transport, wire, {:closed, _reason}}, %{wire: wire} = state),
    do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(
        {:DOWN, monitor, :process, wire, _reason},
        %{pending_monitor: monitor, pending_wire: wire} = state
      ),
      do: {:noreply, discard_pending(state, false)}

  def handle_info(
        {:DOWN, monitor, :process, wire, _reason},
        %{wire_monitor: monitor, wire: wire} = state
      ),
      do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(:setup_timeout, %{ready?: false} = state),
    do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(:renew, %{ready?: true, pending_wire: nil} = state),
    do: {:noreply, start_renewal(state)}

  def handle_info({:pending_timeout, wire}, %{pending_wire: wire} = state),
    do: {:noreply, discard_pending(state)}

  def handle_info({:expire, wire}, %{wire: wire} = state),
    do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :google_stt)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp reduce_event(event, {:ok, state}) do
    case publish(event, state) do
      {:ok, state} -> {:cont, {:ok, state}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp publish(:ready, %{ready?: false} = state) do
    Process.cancel_timer(state.setup_timer)

    with :ok <- Event.emit(state.channel, :ready, readiness: :provider_acknowledged) do
      {:ok, schedule_renewal(%{state | ready?: true, setup_timer: nil})}
    end
  end

  defp publish(:ready, state), do: {:ok, state}

  defp publish(:activity_start, %{active: nil} = state) do
    turn = make_ref()

    case Event.emit(state.channel, :speech_started, turn_ref: turn) do
      :ok -> {:ok, %{state | active: %{ref: turn, final: nil}}}
      :discarded -> {:ok, state}
      error -> error
    end
  end

  defp publish(:activity_start, _state), do: {:error, :overlapping_activity}

  defp publish(:activity_end, %{active: nil} = state), do: {:ok, state}

  defp publish(:activity_end, %{active: active, pending: pending} = state)
       when length(pending) < @maximum_pending_turns do
    finish_turn(%{state | active: nil, pending: pending ++ [active]})
  end

  defp publish(:activity_end, _state), do: {:error, :too_many_pending_turns}

  defp publish({:interim, text}, %{active: %{ref: turn}} = state) do
    emit(state, :transcript, turn_ref: turn, text: text)
  end

  defp publish({:interim, _text}, state), do: {:ok, state}

  defp publish({:final, text}, %{pending: [first | rest]} = state) do
    finish_turn(%{state | pending: [%{first | final: text} | rest]})
  end

  defp publish({:final, text}, %{active: %{final: nil} = active} = state),
    do: {:ok, %{state | active: %{active | final: text}}}

  defp publish({:final, _text}, state), do: {:ok, state}

  defp publish(:go_away, state), do: {:ok, start_renewal(state)}

  defp start_renewal(%{pending_wire: nil, wire: wire} = state) when wire != nil do
    if state.renew_timer, do: Process.cancel_timer(state.renew_timer)

    case start_socket(state, deferred: true) do
      {:ok, pending} ->
        %{
          state
          | pending_wire: pending,
            pending_monitor: Process.monitor(pending),
            pending_ready?: false,
            renew_timer: nil
        }

      _failure ->
        schedule_retry(%{state | renew_timer: nil})
    end
  end

  defp start_renewal(state), do: state

  defp discard_pending(state, close? \\ true) do
    if state.pending_timer, do: Process.cancel_timer(state.pending_timer)
    if state.pending_monitor, do: Process.demonitor(state.pending_monitor, [:flush])
    if close? and state.pending_wire, do: state.wire_module.close(state.pending_wire)

    state
    |> Map.merge(%{
      pending_wire: nil,
      pending_monitor: nil,
      pending_ready?: false,
      pending_timer: nil
    })
    |> schedule_retry()
  end

  defp schedule_retry(state) do
    if state.renew_timer, do: Process.cancel_timer(state.renew_timer)
    %{state | renew_timer: Process.send_after(self(), :renew, @renew_retry)}
  end

  defp maybe_swap(%{pending_ready?: true, active: nil, pending: [], pending_wire: next} = state)
       when next != nil do
    if state.expire_timer, do: Process.cancel_timer(state.expire_timer)
    if state.wire_monitor, do: Process.demonitor(state.wire_monitor, [:flush])
    _ = state.wire_module.close(state.wire)

    state
    |> Map.merge(%{
      wire: next,
      wire_monitor: state.pending_monitor,
      pending_wire: nil,
      pending_monitor: nil,
      pending_ready?: false,
      pending_timer: nil,
      expire_timer: nil
    })
    |> schedule_renewal()
  end

  defp maybe_swap(state), do: state

  defp schedule_renewal(state) do
    if state.renew_timer, do: Process.cancel_timer(state.renew_timer)
    if state.expire_timer, do: Process.cancel_timer(state.expire_timer)

    %{
      state
      | renew_timer: Process.send_after(self(), :renew, @renew_after),
        expire_timer: Process.send_after(self(), {:expire, state.wire}, @expire_after)
    }
  end

  defp finish_turn(%{pending: [%{ref: turn, final: text} | rest]} = state)
       when is_binary(text) do
    with {:ok, state} <-
           emit(state, :turn_ended,
             turn_ref: turn,
             text: text,
             endpointing: :provider_semantic
           ) do
      {:ok, %{state | pending: rest}}
    end
  end

  defp finish_turn(state), do: {:ok, state}

  defp emit(state, kind, fields) do
    case Event.emit(state.channel, kind, fields) do
      :ok -> {:ok, state}
      :discarded -> {:ok, state}
      error -> error
    end
  end

  defp start_socket(state, extra) do
    options =
      [
        owner: self(),
        connection: STT.connection_options(state.config),
        transport_options: state.wire_options
      ] ++ extra

    DynamicSupervisor.start_child(state.socket_supervisor, %{
      id: state.wire_module,
      start: {state.wire_module, :start_link, [options]},
      restart: :temporary,
      shutdown: :brutal_kill
    })
  end
end
