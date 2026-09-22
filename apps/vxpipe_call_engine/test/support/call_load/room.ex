defmodule Vxpipe.CallEngine.CallLoad.Room do
  @moduledoc false
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallSpec,
    CallInvocation,
    CallSpecCompiler,
    TestCallStartup,
    TestTransferConnection
  }

  alias Vxpipe.CallEngine.CallLoad.Sink
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}

  @track %{track_id: "load-mic", codec: :linear16, sample_rate: 16_000, channels: 1}

  def plan(mode) do
    speech = %{provider: "morse", model: "morse", options: %{unit_duration_ms: 20}}

    agent =
      case mode do
        :llm_tts ->
          %{model_inference: %{provider: "fixture", model: "test:load"}, text_to_speech: speech}

        :sts_provider ->
          %{speech_to_speech: speech}

        :sts_output_stt ->
          %{
            speech_to_speech: put_in(speech.options[:output_transcript], false),
            output_speech_to_text: speech
          }
      end

    source = %{
      schema_version: CallSpec.schema_version(),
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "agent",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: if(mode == :llm_tts, do: %{speech_to_text: speech}, else: %{})
        },
        "agent" => %{
          type: "agent",
          prompt: "Reply in Morse.",
          tools: %{},
          transfers: [],
          first_message: %{mode: "wait_for_input"},
          capabilities: agent
        }
      },
      limits: %{max_duration_ms: 100_000}
    }

    {:ok, spec} = CallSpec.new(source, resource_id: "call-load", revision: 1)

    {:ok, invocation} =
      CallInvocation.new(%{call_spec: %{id: "call-load", revision: 1}, transport: %{type: "web"}},
        tenant_id: "load-tenant",
        actor_id: "load-actor"
      )

    {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end

  def start(plan, mode, supervisor) do
    started = now()
    {:ok, room} = CallEngine.start_call(plan)
    admitted = now()
    TestCallStartup.await_prepared(plan)
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    {:ok, command} =
      AttachConnection.new(
        tenant_id: plan.tenant_id,
        actor_id: plan.actor_id,
        room_id: plan.room_id,
        incarnation_id: room.incarnation_id,
        participant_id: caller.participant_id,
        connection_id: "load-#{System.unique_integer([:positive])}",
        deadline: DateTime.add(DateTime.utc_now(), 10, :second)
      )

    {:ok, sink} = DynamicSupervisor.start_child(supervisor, {Sink, observer: self()})

    {:ok, connection} =
      DynamicSupervisor.start_child(
        supervisor,
        {TestTransferConnection,
         command: command, output: sink, observer: self(), input_track: @track}
      )

    {:ok, _attachment} = GenServer.call(connection, :attach)
    TestCallStartup.await_ready(plan.room_id)
    attachment = TestTransferConnection.attachment(command)
    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
    {:dictionary, dictionary} = Process.info(authority, :dictionary)
    [root | _] = Keyword.fetch!(dictionary, :"$ancestors")
    {:ok, config} = Config.new(unit_duration_ms: 20)
    {:ok, pcm} = Encoder.encode(config, "HI")

    %{
      plan: plan,
      mode: mode,
      command: command,
      sink: sink,
      connection: connection,
      attachment: attachment,
      authority: authority,
      root: root,
      pcm: pcm,
      admission_ms: admitted - started,
      startup_ms: now() - started
    }
  end

  def feed(context, turn, observer) do
    chunks = chunks(context.pcm)

    Enum.each(Enum.with_index(chunks, turn * 1_000), fn {pcm, sequence} ->
      frame =
        struct!(
          AudioFrame,
          Map.merge(
            Map.take(
              context.command,
              [:tenant_id, :room_id, :incarnation_id, :participant_id, :connection_id]
            ),
            Map.merge(@track, %{
              payload: pcm,
              sequence_number: sequence,
              timestamp: sequence * 160,
              received_at: System.monotonic_time(:millisecond)
            })
          )
        )

      begin = now()

      result =
        TestTransferConnection.run(context.command, fn ->
          if context.mode == :llm_tts,
            do: CallEngine.push_audio(context.attachment, frame),
            else: CallEngine.push_speech_to_speech_audio(context.attachment, frame)
        end)

      send(observer, {:input_result, result, now() - begin})

      receive do
      after
        10 -> :ok
      end
    end)

    send(observer, {:input_finished, turn})
  end

  def members(root) do
    [
      root
      | Enum.flat_map(Supervisor.which_children(root), fn
          {_, pid, :supervisor, _} when is_pid(pid) -> members(pid)
          {_, pid, _, _} when is_pid(pid) -> [pid]
          _ -> []
        end)
    ]
  catch
    :exit, _ -> [root]
  end

  def cleanup(plan) do
    case Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id}) do
      [{authority, _}] ->
        case Process.info(authority, :dictionary) do
          {:dictionary, dictionary} ->
            [root | _] = Keyword.fetch!(dictionary, :"$ancestors")
            stop(root)

          nil ->
            :ok
        end

      [] ->
        :ok
    end
  end

  def stop_helpers(context, supervisor) do
    Enum.each([context.sink, context.connection], fn pid ->
      ref = Process.monitor(pid)
      :ok = DynamicSupervisor.terminate_child(supervisor, pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        2_000 -> raise "helper cleanup timeout"
      end
    end)
  end

  def stop(root) do
    monitors = Enum.map(members(root), &{&1, Process.monitor(&1)})
    result = DynamicSupervisor.terminate_child(CallEngine.RoomSupervisor, root)
    true = result in [:ok, {:error, :not_found}]

    Enum.each(monitors, fn {pid, ref} ->
      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        2_000 -> raise "room cleanup timeout"
      end
    end)

    length(monitors)
  end

  defp chunks(<<>>), do: []
  defp chunks(<<chunk::binary-size(320), rest::binary>>), do: [chunk | chunks(rest)]
  defp chunks(rest), do: [rest]
  defp now, do: System.monotonic_time(:microsecond) / 1_000
end
