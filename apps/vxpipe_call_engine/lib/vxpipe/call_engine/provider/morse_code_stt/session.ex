defmodule Vxpipe.CallEngine.Provider.MorseCodeSTT.Session do
  @moduledoc "Native raw-PCM Morse recognition; this provider does not recognize human speech."
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STTProvider

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder}
  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event}

  @derive {Inspect, only: [:turn_ref]}
  defstruct [:decoder, :channel, :turn_ref, finished?: false]

  @impl true
  def configure(options) do
    allowed = Map.keys(Config.__struct__()) -- [:__struct__]

    with true <- is_list(options) and Keyword.keyword?(options),
         true <- length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))),
         true <- Enum.all?(Keyword.keys(options), &(&1 in allowed)),
         {:ok, config} <- Config.new(options) do
      Descriptor.new(
        kind: :stt,
        finite_input?: true,
        settings: config,
        format: %{
          encoding: :linear16,
          container: :raw,
          sample_rate: config.sample_rate,
          channels: 1,
          byte_order: :little,
          signed?: true
        },
        usage_identity: %{
          provider: :morse_code,
          model: :morse_code,
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
    descriptor = Keyword.fetch!(options, :descriptor)
    channel = Keyword.fetch!(options, :channel)

    with {:ok, decoder} <- Decoder.new(descriptor.settings),
         :ok <- Channel.bind(channel),
         :ok <- Event.emit(channel, :ready, readiness: descriptor.readiness) do
      {:ok, %__MODULE__{decoder: decoder, channel: channel}}
    else
      _error -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:push_audio, _audio}, _from, %{finished?: true} = state),
    do: {:reply, {:error, :session_failed}, state}

  def handle_call({:push_audio, audio}, _from, state) do
    with {:ok, decoder, events} <- Decoder.push(state.decoder, audio),
         {:ok, state} <- publish(events, %{state | decoder: decoder}) do
      {:reply, :ok, state}
    else
      {:error, reason} -> {:stop, :normal, {:error, reason}, state}
    end
  end

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  def handle_call(:finish_input, _from, %{finished?: true} = state), do: {:reply, :ok, state}

  def handle_call(:finish_input, _from, state) do
    case Decoder.flush(state.decoder) do
      {:ok, decoder, events} ->
        with {:ok, state} <- publish(events, %{state | decoder: decoder}),
             :ok <- Event.emit(state.channel, :input_finished) do
          {:reply, :ok, %{state | finished?: true}}
        else
          _error -> {:reply, {:error, :session_failed}, state}
        end

      {:error, _reason} ->
        {:reply, {:error, :session_failed}, state}
    end
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :morse_stt_session)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp publish([], state), do: {:ok, state}

  defp publish([event | rest], state) do
    {kind, fields, state} = semantic(event, state)
    with :ok <- Event.emit(state.channel, kind, fields), do: publish(rest, state)
  end

  defp semantic(:started, state) do
    state = %{state | turn_ref: make_ref()}
    {:speech_started, [turn_ref: state.turn_ref], state}
  end

  defp semantic({:partial, text}, state),
    do: {:transcript, [turn_ref: state.turn_ref, text: text], state}

  defp semantic({:final, text}, state),
    do:
      {:turn_ended, [turn_ref: state.turn_ref, text: text, endpointing: :provider_gap],
       %{state | turn_ref: nil}}
end
