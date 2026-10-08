defmodule Vxpipe.CallEngine.SpeechOutputSTTSlowProvider do
  @moduledoc "Test-only slow output-STT consumer: busy twice, then completes on finish."

  use GenServer

  @behaviour Vxpipe.CallEngine.Speech.STTProvider

  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event}

  @impl true
  def models, do: [Vxpipe.CallEngine.Speech.Model.new("test", "Test provider", true)]

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
        usage_identity: %{provider: :slow_stt, model: :slow_stt, provenance: :locally_measured},
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

  def release_ready(pid), do: GenServer.call(pid, :release_ready, 5_000)

  @impl true
  def close(pid) do
    GenServer.call(pid, :close, 5_000)
  catch
    :exit, {:noproc, _call} -> :ok
    :exit, {:normal, _call} -> :ok
  end

  @impl true
  def init(options) do
    channel = Keyword.fetch!(options, :channel)
    observer = options |> Keyword.get(:private, []) |> Keyword.get(:ready_observer)

    with :ok <- Channel.bind(channel) do
      if is_pid(observer) do
        send(observer, {:output_stt_waiting, self()})
      else
        :ok = Event.emit(channel, :ready, readiness: :initialized)
      end

      {:ok, %{channel: channel, busy_remaining: 2}}
    else
      _error -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call(:release_ready, _from, state) do
    {:reply, Event.emit(state.channel, :ready, readiness: :initialized), state}
  end

  def handle_call({:push_audio, _audio}, _from, %{busy_remaining: remaining} = state)
      when remaining > 0 do
    {:reply, {:error, :busy}, %{state | busy_remaining: remaining - 1}}
  end

  def handle_call({:push_audio, _audio}, _from, state), do: {:reply, :ok, state}

  def handle_call(:finish_input, _from, state) do
    turn = make_ref()

    with :ok <- Event.emit(state.channel, :speech_started, turn_ref: turn),
         :ok <- Event.emit(state.channel, :transcript, turn_ref: turn, text: "SLOW RESULT"),
         :ok <-
           Event.emit(state.channel, :turn_ended,
             turn_ref: turn,
             text: "SLOW RESULT",
             endpointing: :provider_gap
           ),
         :ok <- Event.emit(state.channel, :input_finished) do
      {:reply, :ok, state}
    else
      _failure -> {:stop, {:shutdown, :session_failed}, {:error, :session_failed}, state}
    end
  end

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :slow_stt_provider)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end
end
