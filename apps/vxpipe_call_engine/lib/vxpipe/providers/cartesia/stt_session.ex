defmodule Vxpipe.Providers.Cartesia.STTSession do
  @moduledoc false
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STTProvider
  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, SessionTree, STTProvider}
  alias Vxpipe.Providers.Cartesia.{STT, STTSocket, STTTurns}
  @setup_timeout 15_000
  @drain_timeout 15_000

  @derive {Inspect, only: [:ready?, :finishing?, :finished?]}
  defstruct [
    :channel,
    :socket_supervisor,
    :config,
    :wire,
    :wire_monitor,
    :wire_module,
    :wire_options,
    :setup_timer,
    :drain_timer,
    turns: nil,
    ready?: false,
    finishing?: false,
    finished?: false
  ]

  @impl true
  defdelegate models(), to: Vxpipe.Providers.Cartesia.STT

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
        usage_identity: %{provider: :cartesia, model: public.model, provenance: :locally_measured},
        readiness: :provider_acknowledged,
        endpointing: :provider_semantic,
        speech_start?: true,
        eager_end?: true,
        resume?: true,
        finite_input?: true
      )
    end
  end

  @impl true
  def start_link(options), do: STTProvider.start_link(__MODULE__, options)
  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:push_audio, audio}, 5_000)
  @impl true
  def finish_input(pid), do: GenServer.call(pid, :finish_input, 5_000)
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
    private = Keyword.fetch!(options, :private)
    config = Keyword.fetch!(private, :config)
    channel = options |> Keyword.fetch!(:channel) |> GenServer.whereis()
    wire_module = Keyword.get(private, :wire_module, STTSocket)
    wire_options = Keyword.get(private, :wire_options, [])

    with %STT{} <- config,
         {:ok, descriptor} <-
           configure(
             model: config.model,
             encoding: config.encoding,
             sample_rate: config.sample_rate
           ),
         true <- descriptor == Keyword.fetch!(options, :descriptor),
         true <- is_atom(wire_module) and Keyword.keyword?(wire_options),
         :ok <- Channel.bind(channel) do
      {:ok,
       %__MODULE__{
         channel: channel,
         config: config,
         wire_module: wire_module,
         wire_options: wire_options,
         socket_supervisor: SessionTree.providers(allocation),
         turns: STTTurns.new()
       }, {:continue, :connect}}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_continue(:connect, state) do
    options = [
      owner: self(),
      connection: STT.connection_options(state.config),
      transport_options: state.wire_options
    ]

    case DynamicSupervisor.start_child(state.socket_supervisor, %{
           id: state.wire_module,
           start: {state.wire_module, :start_link, [options]},
           restart: :temporary,
           shutdown: :brutal_kill
         }) do
      {:ok, wire} ->
        {:noreply,
         %{
           state
           | wire: wire,
             wire_monitor: Process.monitor(wire),
             setup_timer: Process.send_after(self(), :setup_timeout, @setup_timeout)
         }}

      _failure ->
        {:stop, {:shutdown, :session_failed}, state}
    end
  end

  @impl true
  def handle_call(
        {:push_audio, audio},
        _from,
        %{ready?: true, finishing?: false, finished?: false} = state
      ) do
    with :ok <- STT.validate_audio(audio),
         :ok <- wire_call(state, :send_audio, [audio]) do
      {:reply, :ok, state}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call({:push_audio, _audio}, _from, state),
    do: {:reply, {:error, :session_failed}, state}

  def handle_call(:finish_input, _from, %{finishing?: true} = state), do: {:reply, :ok, state}
  def handle_call(:finish_input, _from, %{finished?: true} = state), do: {:reply, :ok, state}

  def handle_call(:finish_input, _from, %{ready?: true} = state) do
    case wire_call(state, :finish_input, []) do
      :ok ->
        {:reply, :ok,
         %{
           state
           | finishing?: true,
             drain_timer: Process.send_after(self(), :drain_timeout, @drain_timeout)
         }}

      _failure ->
        {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call(:finish_input, _from, state), do: {:reply, {:error, :session_failed}, state}

  def handle_call(:close, _from, state) do
    if state.wire, do: DynamicSupervisor.terminate_child(state.socket_supervisor, state.wire)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:vxpipe_stt_transport, wire, {:message, payload}}, %{wire: wire} = state) do
    with {:ok, event} <- STT.decode(payload),
         {:ok, turns, {kind, fields}} <- STTTurns.advance(state.turns, event),
         result when result in [:ok, :discarded] <- Event.emit(state.channel, kind, fields) do
      state = %{state | turns: turns}

      state =
        if kind == :ready do
          Process.cancel_timer(state.setup_timer)
          %{state | ready?: true, setup_timer: nil}
        else
          state
        end

      {:noreply, state}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info(
        {:vxpipe_stt_transport, wire, {:peer_closed, :normal_or_no_status}},
        %{wire: wire, finishing?: true} = state
      ) do
    with true <- STTTurns.finished?(state.turns),
         :ok <- Event.emit(state.channel, :input_finished) do
      Process.cancel_timer(state.drain_timer)
      Process.demonitor(state.wire_monitor, [:flush])

      {:noreply,
       %{
         state
         | wire: nil,
           wire_monitor: nil,
           drain_timer: nil,
           finishing?: false,
           finished?: true
       }}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, state}
    end
  end

  def handle_info({:vxpipe_stt_transport, wire, {_closed, _reason}}, %{wire: wire} = state),
    do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(
        {:DOWN, monitor, :process, wire, _reason},
        %{wire_monitor: monitor, wire: wire} = state
      ),
      do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(:setup_timeout, %{ready?: false} = state),
    do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(:drain_timeout, %{finishing?: true} = state),
    do: {:stop, {:shutdown, :session_failed}, state}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :cartesia_stt)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp wire_call(state, operation, arguments) do
    apply(state.wire_module, operation, [state.wire | arguments])
  catch
    :exit, _reason -> {:error, :connection_lost}
  end
end
