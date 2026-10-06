defmodule Vxpipe.CallEngine.OutgoingCallReviewTest do
  @moduledoc """
  Reproductions from the 2026-10-06 outgoing-call review
  (docs/milestones/outgoing-call-review-fixes.md). Each test states the
  specified behavior and failed when written.
  """

  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler}
  alias Vxpipe.CallEngine.{TestCallLifecycleTimer, TestOutboundLegConnector}
  alias Vxpipe.CallEngine.TestSelectiveAgentRuntimeModelProvider

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:fixture, {TestSelectiveAgentRuntimeModelProvider, [owner: self()]})

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :agent_runtime, runtime)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  # Issue 1: the carrier reported the callee answered (machine detection pending), so a
  # later remote hangup is an answered call ending, not a decline before answer.
  test "a hangup after a physical answer awaiting machine classification is not rejected" do
    plan = plan()
    assert {:ok, _room} = start_call(plan)
    assert_receive {:test_outbound_leg_connect, _, request, _}, 1_000
    owner = authority(plan)
    monitor = Process.monitor(owner)

    send(owner, {:vxpipe_outbound_leg, request.attempt_id, self(), :connected})
    assert_receive {:test_call_lifecycle_timer_cancelled, {^owner, _, :outgoing_ring}}, 1_000

    assert_receive {:test_archive_fact,
                    %CallEngine.Archive.Fact{
                      kind: :outgoing_call_answered,
                      occurred_at: %DateTime{}
                    }},
                   1_000

    send(owner, {:vxpipe_outbound_leg, request.attempt_id, self(), {:ended, :hangup}})

    assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, {:outgoing_call, outcome}}},
                   1_000

    assert outcome == :answered
  end

  defp start_call(plan) do
    CallEngine.start_call(plan,
      outbound_leg_connector: {TestOutboundLegConnector, %{observer: self(), owner: self()}},
      archive: [
        enabled: true,
        writer: {CallEngine.TestCollectingArchiveWriter, self()},
        maximum_pending_facts: 64,
        retry_delay_ms: 5,
        drain_timeout_ms: 1_000
      ],
      call_lifecycle: [
        readiness_timeout_ms: 30_000,
        idle_timeout_ms: 15_000,
        outgoing_clock: fn -> System.monotonic_time(:millisecond) end,
        timer: {TestCallLifecycleTimer, [observer: self()]}
      ]
    )
  end

  defp plan do
    input = %{
      schema_version: CallSpec.schema_version(),
      outgoing_call: %{callee: "customer", handled_by: "assistant", ring_timeout_ms: 5_000},
      defaults: %{capabilities: %{}},
      wait_sounds: nil,
      call_variables: %{sections: %{}},
      participants: %{
        "customer" => %{
          type: "human",
          connection: %{service: "phone", mode: "dial", number: "+15550001001"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Introduce yourself.",
          tools: %{},
          transfers: [],
          capabilities: %{model_inference: %{provider: "fixture", model: "test:scripted"}}
        }
      },
      limits: %{max_duration_ms: 60_000}
    }

    assert {:ok, spec} = CallSpec.new(input, resource_id: "outgoing-review", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "outgoing-review", revision: 1},
                 transport: %{type: "telephony"},
                 initial_variables: %{}
               },
               tenant_id: "tenant-review",
               actor_id: "actor-review",
               call_id: unique("call"),
               room_id: unique("room")
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end

  defp authority(plan) do
    [{owner, _}] = Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
    owner
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
