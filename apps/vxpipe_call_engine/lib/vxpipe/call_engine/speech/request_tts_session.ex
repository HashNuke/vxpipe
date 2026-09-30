defmodule Vxpipe.CallEngine.Speech.RequestTTSSession do
  @moduledoc "Owns one credited complete-phrase request task at a time."
  use GenServer

  alias Vxpipe.CallEngine.Speech.{Channel, Event, Playback, SessionTree, TTSProvider}

  @request_timeout 60_000
  @credit_timeout 20_000

  @derive {Inspect, only: [:request, :last_terminal_request]}
  defstruct [
    :channel,
    :provider,
    :config,
    :request_module,
    :command_supervisor,
    :task,
    :request,
    :last_terminal_request,
    :request_timer,
    :awaiting
  ]

  def start_link(options, provider),
    do: TTSProvider.start_link(__MODULE__, Keyword.put(options, :request_provider, provider))

  def speak(pid, reference, text), do: GenServer.call(pid, {:speak, reference, text}, 5_000)

  def cancel(pid, reference, playback),
    do: GenServer.call(pid, {:cancel, reference, playback}, 5_000)

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
    provider = Keyword.fetch!(options, :request_provider)

    with {:ok, expected, default_request} <- provider.request_configuration(config),
         true <- descriptor == expected,
         request_module = Keyword.get(private, :request_module, default_request),
         true <- is_atom(request_module),
         :ok <- Channel.bind(channel),
         :ok <- Event.emit(channel, :ready, readiness: :initialized) do
      {:ok,
       %__MODULE__{
         channel: channel,
         provider: provider,
         config: config,
         request_module: request_module,
         command_supervisor: SessionTree.commands(allocation)
       }}
    else
      _invalid -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:speak, reference, text}, _from, %{request: nil} = state) do
    with :ok <- state.provider.validate_text(text),
         :ok <-
           Event.emit(state.channel, :input_submitted,
             request_ref: reference,
             provenance: :locally_measured
           ) do
      owner = self()

      task =
        Task.Supervisor.async_nolink(state.command_supervisor, fn ->
          consume = fn audio ->
            tag = make_ref()
            send(owner, {:request_tts_audio, reference, tag, audio})

            receive do
              {:request_tts_credit, ^tag} -> :ok
            after
              @credit_timeout -> {:error, :credit_timeout}
            end
          end

          state.request_module.run(state.config, text, consume)
        end)

      timer = Process.send_after(self(), {:request_timeout, reference}, @request_timeout)
      {:reply, :ok, %{state | request: reference, task: task, request_timer: timer}}
    else
      {:error, :invalid_text} -> {:reply, {:error, :invalid_text}, state}
      _failure -> {:stop, :normal, {:error, :provider_unavailable}, state}
    end
  end

  def handle_call({:speak, _reference, _text}, _from, state),
    do: {:reply, {:error, :busy}, state}

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: nil, last_terminal_request: reference} = state
      ),
      do: {:reply, :ok, state}

  def handle_call(
        {:cancel, reference, %Playback{request_ref: reference}},
        _from,
        %{request: reference} = state
      ) do
    _ = Task.shutdown(state.task, :brutal_kill)
    Process.cancel_timer(state.request_timer)

    case Event.emit(state.channel, :cancelled, request_ref: reference) do
      :ok ->
        {:reply, :ok,
         %{
           state
           | request: nil,
             last_terminal_request: reference,
             task: nil,
             request_timer: nil,
             awaiting: nil
         }}

      _failure ->
        {:stop, :normal, {:error, :provider_unavailable}, state}
    end
  end

  def handle_call({:cancel, _reference, _playback}, _from, state),
    do: {:reply, {:error, :stale_request}, state}

  def handle_call(:close, _from, state) do
    if state.task, do: Task.shutdown(state.task, :brutal_kill)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info(
        {:request_tts_audio, reference, tag, audio},
        %{request: reference, awaiting: nil} = state
      ) do
    case Channel.submit(state.channel, reference, audio) do
      {:ok, credit} -> {:noreply, %{state | awaiting: {credit, tag}}}
      _failure -> {:stop, :normal, state}
    end
  end

  def handle_info(
        {:vxpipe_speech_credit, channel, request, credit, :ok},
        %{channel: channel, request: request, awaiting: {credit, tag}, task: task} = state
      ) do
    send(task.pid, {:request_tts_credit, tag})
    {:noreply, %{state | awaiting: nil}}
  end

  def handle_info({task_ref, :ok}, %{task: %Task{ref: task_ref}, request: request} = state) do
    Process.demonitor(task_ref, [:flush])
    Process.cancel_timer(state.request_timer)

    case Event.emit(state.channel, :completed, request_ref: request) do
      :ok ->
        {:noreply,
         %{state | request: nil, last_terminal_request: request, task: nil, request_timer: nil}}

      _failure ->
        {:stop, :normal, state}
    end
  end

  def handle_info({task_ref, _error}, %{task: %Task{ref: task_ref}} = state),
    do: {:stop, :normal, state}

  def handle_info(
        {:DOWN, task_ref, :process, _pid, _reason},
        %{task: %Task{ref: task_ref}} = state
      ),
      do: {:stop, :normal, state}

  def handle_info({:request_timeout, request}, %{request: request} = state),
    do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.task, do: Task.shutdown(state.task, :brutal_kill)
    :ok
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :request_tts)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end
end
