defmodule Vxpipe.CallEngine.SpeechTopologyPrototype do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.{SpeechTopologySession, SpeechTopologySTT, SpeechTopologyUsage}
  alias Vxpipe.CallEngine.SpeechTopologyPrototype.Session

  @registry Module.concat(__MODULE__, Registry)
  @sessions Module.concat(__MODULE__, Sessions)
  @timeout 1_000

  def start!(topology, consumer, usage, observer \\ nil)
      when topology in [:split, :merged] and is_pid(consumer) and is_pid(usage) do
    reference = make_ref()
    observer = observer || consumer
    {:ok, config} = Config.new(sample_rate: 8_000, unit_duration_ms: 20)

    {:ok, supervisor} =
      DynamicSupervisor.start_child(
        @sessions,
        {SpeechTopologySession, {topology, reference, consumer, observer, usage, config}}
      )

    %Session{
      topology: topology,
      ref: reference,
      supervisor: supervisor,
      channel: whereis(reference, :channel),
      input: whereis(reference, :input),
      provider: whereis(reference, :provider),
      output: if(topology == :split, do: whereis(reference, :output), else: nil),
      usage: usage,
      timeout: @timeout
    }
  end

  def prepare(session) do
    call(session.channel, {:prepare, %{sample_rate: 8_000, channels: 1}}, session.timeout)
  end

  def speak(session, text, options \\ []) when is_binary(text),
    do: call(session.channel, {:speak, text, options}, session.timeout)

  def fence(session, request),
    do: call(session.channel, {:fence, request}, session.timeout)

  def cancel(session, ticket, played_ms),
    do: call(session.channel, {:cancel, ticket, played_ms}, session.timeout)

  def ack_event(session, event),
    do: call(session.channel, {:ack_event, event}, session.timeout)

  def validate_audio(%Session{topology: :split} = session, audio),
    do: call(session.output, {:validate_audio, audio}, session.timeout)

  def validate_audio(%Session{topology: :merged} = session, audio),
    do: call(session.channel, {:validate_audio, audio}, session.timeout)

  def ack_audio(%Session{topology: :split} = session, audio),
    do: call(session.output, {:ack_audio, audio}, session.timeout)

  def ack_audio(%Session{topology: :merged} = session, audio),
    do: call(session.channel, {:ack_audio, audio}, session.timeout)

  def sync(session), do: call(session.channel, :sync, session.timeout)

  def release(input, reference), do: send(input, {:release_topology_input, reference})

  def close(%Session{supervisor: supervisor}) do
    case DynamicSupervisor.terminate_child(@sessions, supervisor) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  catch
    :exit, _reason -> :ok
  end

  def process_count(session), do: Supervisor.count_children(session.supervisor).active

  def stt_child_spec(owner),
    do: Supervisor.child_spec({SpeechTopologySTT, owner}, id: make_ref(), restart: :temporary)

  def stt_turn(stt, reference, pcm),
    do: GenServer.call(stt, {:turn, reference, pcm}, @timeout)

  def usage_child_spec,
    do: Supervisor.child_spec({SpeechTopologyUsage, nil}, id: make_ref(), restart: :temporary)

  def take_usage(usage, request), do: SpeechTopologyUsage.take(usage, request)

  def pcm(text) do
    {:ok, config} = Config.new(sample_rate: 8_000, unit_duration_ms: 20)
    {:ok, pcm} = Encoder.encode(config, text)
    pcm
  end

  def registry, do: @registry
  def sessions, do: @sessions

  def address(reference, role), do: {:via, Registry, {@registry, {reference, role}}}

  defp call(target, operation, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    GenServer.call(target, {:consumer, deadline, operation}, timeout)
  catch
    :exit, {:timeout, _call} -> {:error, :command_timeout}
    :exit, _reason -> {:error, :closed}
  end

  defp whereis(reference, role) do
    [{pid, nil}] = Registry.lookup(@registry, {reference, role})
    pid
  end
end
