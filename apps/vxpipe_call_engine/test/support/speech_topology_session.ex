defmodule Vxpipe.CallEngine.SpeechTopologySession do
  @moduledoc false
  use Supervisor

  alias Vxpipe.CallEngine.{
    SpeechTopologyInput,
    SpeechTopologyMergedChannel,
    SpeechTopologyPrototype,
    SpeechTopologyProvider,
    SpeechTopologySplitChannel,
    SpeechTopologySplitOutput
  }

  def child_spec(options) do
    %{
      id: make_ref(),
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      type: :supervisor
    }
  end

  def start_link(options), do: Supervisor.start_link(__MODULE__, options)

  @impl true
  def init({topology, reference, consumer, observer, usage, config}) do
    channel = SpeechTopologyPrototype.address(reference, :channel)
    input = SpeechTopologyPrototype.address(reference, :input)
    provider = SpeechTopologyPrototype.address(reference, :provider)
    output = SpeechTopologyPrototype.address(reference, :output)

    channel_child =
      case topology do
        :split ->
          {SpeechTopologySplitChannel,
           name: channel,
           consumer: consumer,
           observer: observer,
           usage: usage,
           input: input,
           output: output,
           provider: provider}

        :merged ->
          {SpeechTopologyMergedChannel,
           name: channel,
           consumer: consumer,
           observer: observer,
           usage: usage,
           input: input,
           provider: provider}
      end

    output_children =
      if topology == :split do
        [
          {SpeechTopologySplitOutput,
           name: output, channel: channel, provider: provider, consumer: consumer}
        ]
      else
        []
      end

    target = if topology == :split, do: output, else: channel

    children =
      [channel_child] ++
        output_children ++
        [
          {SpeechTopologyInput,
           name: input, consumer: consumer, channel: channel, provider: provider},
          {SpeechTopologyProvider,
           name: provider, channel: channel, input: input, target: target, config: config}
        ]

    children =
      Enum.map(children, &Supervisor.child_spec(&1, restart: :temporary, significant: true))

    Supervisor.init(children, strategy: :one_for_all, auto_shutdown: :any_significant)
  end
end
