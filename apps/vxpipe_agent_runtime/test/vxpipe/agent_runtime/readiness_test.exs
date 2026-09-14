defmodule Vxpipe.AgentRuntime.ReadinessTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Session, TestModelProvider, TestPendingContextSource}

  test "reports installed context and model initialization without submitting a request" do
    session = start_session(:first)

    assert {:ok, evidence, :ready} = Session.readiness(session)
    assert evidence.instance == session
    assert is_reference(evidence.generation)
    assert byte_size(evidence.configuration) == 32
    refute inspect(evidence) =~ "private-context-sentinel"
    refute_receive {:model_provider_process, _pid, _request}

    assert :ok = Session.record_assistant(session, "A completed opening.", %{turn_id: "opening"})
    assert {:ok, ^evidence, :ready} = Session.readiness(session)

    changed = start_session(:changed, instructions: "Different installed context")
    assert {:ok, changed_evidence, :ready} = Session.readiness(changed)
    refute changed_evidence.configuration == evidence.configuration
    refute changed_evidence.generation == evidence.generation
  end

  test "a busy session retains initialization while request admission still rejects overlap" do
    session = start_session(:busy, model: %{mode: :block, test_owner: self()})
    assert {:ok, evidence, :ready} = Session.readiness(session)

    supervisor = start_supervised!({Task.Supervisor, name: unique_name()})

    caller =
      Task.Supervisor.async_nolink(supervisor, fn -> Session.request(session, "Hello", %{}) end)

    assert_receive {:model_provider_process, provider, _request}
    monitor = Process.monitor(provider)

    assert {:ok, ^evidence, :ready} = Session.readiness(session)
    assert {:error, :busy} = Session.request(session, "Overlapping request", %{})
    assert :ok = Session.cancel(session)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _reason}
    assert {:ok, %{status: :cancelled}} = Task.await(caller)
    assert {:ok, ^evidence, :ready} = Session.readiness(session)
  end

  test "missing or failed provider initialization contracts fail closed" do
    unsupported =
      start_session(:unsupported, model_provider: Vxpipe.AgentRuntime.TestStreamingModelProvider)

    assert {:ok, _evidence, :failed} = Session.readiness(unsupported)

    failed = start_session(:failed, model: %{readiness: :failed, test_owner: self()})
    assert {:ok, _evidence, :failed} = Session.readiness(failed)
    refute_receive {:model_provider_process, _pid, _request}
  end

  defp start_session(id, options \\ []) do
    options =
      Keyword.merge(
        [
          instructions: "private-context-sentinel",
          model_provider: TestModelProvider,
          model: %{reply: "unused", test_owner: self()},
          pending_context_source: {TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
          event_destination: self()
        ],
        options
      )

    start_supervised!(Supervisor.child_spec({Session, options}, id: id))
  end

  defp unique_name, do: {:global, {__MODULE__, make_ref()}}
end
