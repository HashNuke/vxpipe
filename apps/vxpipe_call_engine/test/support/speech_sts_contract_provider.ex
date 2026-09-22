defmodule Vxpipe.CallEngine.SpeechSTSContractProvider do
  use GenServer
  @behaviour Vxpipe.CallEngine.Speech.STSProvider

  alias Vxpipe.CallEngine.Provider.MorseCodeSTS.Session, as: MorseSTS
  alias Vxpipe.CallEngine.Speech.{Channel, Descriptor, Event, STSProvider}

  @impl true
  def configure(options) do
    {input_transcript?, options} = Keyword.pop(options, :input_transcript, true)

    with {:ok, descriptor} <- MorseSTS.configure(options),
         descriptor = %{descriptor | input_transcript?: input_transcript?},
         :ok <- Descriptor.validate(descriptor) do
      {:ok, descriptor}
    end
  end

  @impl true
  def start_link(options), do: STSProvider.start_link(__MODULE__, options)
  @impl true
  def push_audio(pid, audio), do: GenServer.call(pid, {:audio, audio})
  @impl true
  def push_text(pid, reference, text), do: GenServer.call(pid, {:text, reference, text})
  @impl true
  def input_activity(pid, boundary), do: GenServer.call(pid, {:activity, boundary})
  @impl true
  def interrupt(_pid, _ref), do: {:error, :unsupported_operation}
  @impl true
  def send_tool_result(pid, ref, result), do: GenServer.call(pid, {:tool_result, ref, result})
  @impl true
  def close(pid), do: GenServer.stop(pid)

  @impl true
  def init(options) do
    channel = Keyword.fetch!(options, :channel)
    private = Keyword.fetch!(options, :private)
    :ok = Channel.bind(channel)
    :ok = Event.emit(channel, :ready, readiness: :initialized)

    {:ok,
     %{
       channel: channel,
       mode: Keyword.get(private, :mode, :normal),
       observer: Keyword.fetch!(private, :observer),
       inputs: []
     }}
  end

  @impl true
  def handle_call({:text, reference, text}, _from, state) do
    results =
      case state.mode do
        :duplicate -> [submitted(state, reference), submitted(state, reference)]
        :normal -> [submitted(state, reference)]
      end

    send(state.observer, {:text_submission, reference, results})
    {:reply, :ok, %{state | inputs: [{:text, reference, text} | state.inputs]}}
  end

  def handle_call({:audio, audio}, _from, state),
    do: {:reply, :ok, %{state | inputs: [{:audio, audio} | state.inputs]}}

  def handle_call({:activity, boundary}, _from, state),
    do: {:reply, :ok, %{state | inputs: [{:activity, boundary} | state.inputs]}}

  def handle_call(:inputs, _from, state), do: {:reply, Enum.reverse(state.inputs), state}

  def handle_call({:tool_result, ref, result}, _from, state) do
    send(state.observer, {:contract_tool_result, ref, result})
    {:reply, :ok, state}
  end

  def handle_call({:emit, kind, fields}, _from, state),
    do: {:reply, Event.emit(state.channel, kind, fields), state}

  def handle_call({:output, reference}, _from, state),
    do: {:reply, Channel.submit(state.channel, reference, :binary.copy(<<0, 0>>, 320)), state}

  @impl true
  def handle_info({:vxpipe_speech_output_settled, _, _, _, _} = settled, state) do
    send(state.observer, settled)
    {:noreply, state}
  end

  def handle_info({:vxpipe_speech_output, channel, turn, reference}, state) do
    send(state.observer, {:sts_output_permitted, self(), channel, turn, reference})
    {:noreply, state}
  end

  def handle_info({:vxpipe_speech_credit, _, _, _, _} = credit, state) do
    send(state.observer, credit)
    {:noreply, state}
  end

  defp submitted(state, reference),
    do:
      Event.emit(state.channel, :input_submitted,
        request_ref: reference,
        provenance: :locally_measured
      )
end
