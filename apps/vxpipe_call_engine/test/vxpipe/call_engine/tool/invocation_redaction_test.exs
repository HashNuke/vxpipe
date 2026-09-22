defmodule Vxpipe.CallEngine.Tool.InvocationRedactionTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Vxpipe.CallEngine.TestSubmittedHostTool
  alias Vxpipe.CallEngine.Tool.{Context, Invocation, InvocationBinding, InvocationSupervisor}

  @argument "synthetic-invocation-argument-canary"
  @message "synthetic-invocation-message-canary"

  setup do
    previous = Application.fetch_env(:vxpipe_call_engine, :submitted_host_tool_observer)
    Application.put_env(:vxpipe_call_engine, :submitted_host_tool_observer, self())

    on_exit(fn ->
      case previous do
        {:ok, value} ->
          Application.put_env(:vxpipe_call_engine, :submitted_host_tool_observer, value)

        :error ->
          Application.delete_env(:vxpipe_call_engine, :submitted_host_tool_observer)
      end
    end)

    supervisor =
      start_supervised!(
        Supervisor.child_spec(
          {InvocationSupervisor,
           activation_id: "privacy-test",
           maximum_children: 1,
           name: {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, make_ref()}}}},
          restart: :temporary
        )
      )

    binding = %InvocationBinding{
      name: "submitted_host_tool",
      conversation_mode: :blocking,
      handler: {:host, TestSubmittedHostTool}
    }

    assert {:ok, invocation} =
             InvocationSupervisor.start_invocation(supervisor,
               invocation_id: "privacy-invocation",
               binding: binding,
               arguments: %{"value" => @argument},
               context: context(),
               reply_to: self(),
               timeout_ms: 5_000,
               maximum_result_bytes: 65_536
             )

    assert_receive {:submitted_host_tool_started, task, @argument}
    %{supervisor: supervisor, invocation: invocation, task: task}
  end

  for failure <- [:parent_loss, :worker_termination] do
    test "#{failure} captures a real crash without exposing arguments", context do
      invocation_monitor = Process.monitor(context.invocation)
      task_monitor = Process.monitor(context.task)

      log =
        capture_log(fn ->
          assert :ok = :sys.log(context.invocation, true)
          send(context.invocation, {:ignored_private_message, @message})
          _ = :sys.get_state(context.invocation)

          case unquote(failure) do
            :parent_loss ->
              Process.exit(context.supervisor, :kill)

            :worker_termination ->
              :sys.terminate(context.invocation, :privacy_test_failure)
              _ = :sys.get_state(context.supervisor)
          end

          assert_receive {:DOWN, ^invocation_monitor, :process, _, _}, 1_000
          assert_receive {:DOWN, ^task_monitor, :process, _, _}, 1_000
        end)

      assert log =~ "GenServer"
      assert log =~ "terminating"
      refute log =~ @argument
      refute log =~ @message
    end
  end

  test "ordinary diagnostic status redacts stored arguments", context do
    status = inspect(:sys.get_status(context.invocation), limit: :infinity)
    refute status =~ @argument
  end

  test "formatter sanitizes state, message, reason and diagnostic log" do
    status =
      Invocation.format_status(%{
        state: @argument,
        message: @message,
        reason: {:private, @argument},
        log: [@message]
      })

    assert status == %{state: :tool_invocation, message: :redacted, reason: :redacted, log: []}
  end

  defp context do
    %Context{
      tenant_id: "tenant-privacy",
      room_id: "room-privacy",
      incarnation_id: "incarnation-privacy",
      agent_participant_id: "agent",
      source_participant_id: "caller",
      connection_id: "source",
      command_id: "command-privacy",
      correlation_id: "turn-privacy"
    }
  end
end
