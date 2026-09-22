defmodule Vxpipe.CallEngine.Provider.MorseCodeSTS.Session do
  @moduledoc "Local credential-free speech-to-speech proof provider (checkpoint A selection only)."
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STSProvider

  alias Vxpipe.CallEngine.Provider.MorseCode.Config
  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event}

  @turn_controls ["provider", "external", "hybrid"]

  @impl true
  def configure(options) do
    allowed = (Map.keys(Config.__struct__()) -- [:__struct__]) ++ [:turn_control]

    with true <- is_list(options) and Keyword.keyword?(options),
         true <- length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))),
         true <- Enum.all?(Keyword.keys(options), &(&1 in allowed)),
         {turn_control, rest} = Keyword.pop(options, :turn_control, "provider"),
         true <- turn_control in @turn_controls,
         {:ok, config} <- Config.new(rest) do
      Descriptor.new(
        kind: :sts,
        settings: Map.put(Map.from_struct(config), :turn_control, turn_control),
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
    do: Vxpipe.CallEngine.Speech.STSProvider.start_link(__MODULE__, options)

  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:push_audio, audio}, 5_000)

  @impl true
  def push_text(pid, text) when is_binary(text),
    do: GenServer.call(pid, {:push_text, text}, 5_000)

  @impl true
  def interrupt(pid, turn_ref) when is_reference(turn_ref),
    do: GenServer.call(pid, {:interrupt, turn_ref}, 5_000)

  @impl true
  def send_tool_result(pid, call_ref, result) when is_reference(call_ref),
    do: GenServer.call(pid, {:send_tool_result, call_ref, result}, 5_000)

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

    with :ok <- Channel.bind(channel),
         :ok <- Event.emit(channel, :ready, readiness: descriptor.readiness) do
      {:ok, %{channel: channel, descriptor: descriptor}}
    else
      _error -> {:stop, :initialization_failed}
    end
  end

  @impl true
  def handle_call({:push_audio, audio}, _from, state) when is_binary(audio) do
    {:reply, :ok, state}
  end

  def handle_call({:push_text, _text}, _from, state) do
    {:reply, {:error, :unsupported_operation}, state}
  end

  def handle_call({:interrupt, _turn_ref}, _from, state) do
    {:reply, {:error, :unsupported_operation}, state}
  end

  def handle_call({:send_tool_result, _call_ref, _result}, _from, state) do
    {:reply, {:error, :unsupported_operation}, state}
  end

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :morse_code_sts_session)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end
end
