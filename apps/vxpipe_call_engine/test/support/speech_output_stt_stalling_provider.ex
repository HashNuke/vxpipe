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
    channel = Keyword.fetch!(options, :channel)

    with :ok <- Channel.bind(channel),
         :ok <- Event.emit(channel, :ready, readiness: :initialized) do
      {:ok, %{channel: channel}}
    else
      _error -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:push_audio, _audio}, _from, state), do: {:reply, :ok, state}

  def handle_call(:finish_input, _from, state), do: {:reply, :ok, state}

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :stalling_stt_provider)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
  end
end
