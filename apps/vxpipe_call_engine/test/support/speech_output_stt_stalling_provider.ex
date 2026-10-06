defmodule Vxpipe.CallEngine.SpeechOutputSTTStallingProvider do
  @moduledoc "Test-only output-STT consumer that accepts audio and finalization but never answers."

  use GenServer

  @behaviour Vxpipe.CallEngine.Speech.STTProvider

  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event}

  @impl true
  def configure(options) do
    with true <- is_list(options) and Keyword.keyword?(options) do
      Descriptor.new(
        kind: :stt,
        finite_input?: true,
        settings: %{},
        format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: 16_000,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        usage_identity: %{
          provider: :stalling_stt,
          model: :stalling_stt,
          provenance: :locally_measured
        },
        readiness: :initialized,
        endpointing: :provider_gap,
        speech_start?: true
      )
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def start_link(options),
    do: Vxpipe.CallEngine.Speech.STTProvider.start_link(__MODULE__, options)

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
    private = Keyword.get(options, :private, [])

    attempt =
      case Keyword.get(private, :start_counter) do
        nil -> 1
        counter -> Agent.get_and_update(counter, fn count -> {count + 1, count + 1} end)
      end

    if attempt > 1, do: {:stop, :injected_restart_failure}, else: initialize(options)
  end

  defp initialize(options) do
    channel = Keyword.fetch!(options, :channel)
    private = Keyword.get(options, :private, [])

    with :ok <- Channel.bind(channel),
         :ok <- Event.emit(channel, :ready, readiness: :initialized) do
      if observer = Keyword.get(private, :observer),
        do: send(observer, {:output_stt_started, self()})

      {:ok, %{channel: channel, finish_error: Keyword.get(private, :finish_error)}}
    else
      _error -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:push_audio, _audio}, _from, state), do: {:reply, :ok, state}

  def handle_call(:finish_input, _from, %{finish_error: nil} = state), do: {:reply, :ok, state}

  def handle_call(:finish_input, _from, state),
    do: {:reply, {:error, state.finish_error}, state}

  def handle_call({:emit, kind, fields}, _from, state),
    do: {:reply, Event.emit(state.channel, kind, fields), state}

  def handle_call({:finish_error, reason}, _from, state),
    do: {:reply, :ok, %{state | finish_error: reason}}

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  @impl true
  def handle_cast({:emit, kind, fields}, state) do
    _ = Event.emit(state.channel, kind, fields)
    {:noreply, state}
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :stalling_stt_provider)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
  end
end
