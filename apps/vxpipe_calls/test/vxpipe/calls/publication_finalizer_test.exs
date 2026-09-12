defmodule Vxpipe.Calls.PublicationFinalizerTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Calls.{
    CallDetailsAssessment,
    CallDetailsSource,
    PublicationComponent,
    TestPublicationArtifactWriter,
    TestPublicationClock,
    TestPublicationRepository,
    TestPublicationSource,
    TestPublicationTimer
  }

  @tenant_key "TENANT001"
  @call_id "call-finalizer"
  @ended_at ~U[2026-09-12 18:00:00.000Z]
  @published_at ~U[2026-09-12 18:01:02.000Z]

  test "polls outside the room and publishes pending facts at the reporting deadline" do
    observer = self()
    clock = start_agent(fn -> ~U[2026-09-12 18:00:30.000Z] end)
    repository = repository(observer)
    source = source_agent(observer, {:ok, assessment(:pending)})
    finalizer_options = options(observer, repository, source, clock)

    assert {:ok, finalizer, :started} =
             Vxpipe.Calls.finalize_call_details(
               @tenant_key,
               @call_id,
               finalizer_options
             )

    finalizer_monitor = Process.monitor(finalizer)

    assert_receive {:publication_source_read, ^finalizer, @tenant_key, @call_id}
    assert_receive {:publication_timer_scheduled, ^finalizer, token, 5_000}
    refute_received {:publication_reserved, _, _, _}

    assert {:ok, ^finalizer, :existing} =
             Vxpipe.Calls.finalize_call_details(
               @tenant_key,
               @call_id,
               finalizer_options
             )

    Agent.update(clock, fn _time -> ~U[2026-09-12 18:01:00.000Z] end)
    send(finalizer, {:vxpipe_publication_timer, token})

    assert_receive {:publication_source_read, ^finalizer, @tenant_key, @call_id}
    assert_receive {:publication_reserved, _attempt, @tenant_key, @call_id}
    assert_receive {:vxpipe_call_details_published, worker, _publication_id, 1}

    assert_receive {:vxpipe_call_details_finalization_submitted, ^finalizer, ^worker, :started,
                    :incomplete}

    assert_receive {:DOWN, ^finalizer_monitor, :process, ^finalizer, :normal}
  end

  test "retries a failed source read and publishes once facts become available" do
    observer = self()
    clock = start_agent(fn -> ~U[2026-09-12 18:00:10.000Z] end)
    repository = repository(observer)
    source = source_agent(observer, {:error, :database_unavailable})

    assert {:ok, finalizer, :started} =
             Vxpipe.Calls.finalize_call_details(
               @tenant_key,
               @call_id,
               options(observer, repository, source, clock)
             )

    assert_receive {:vxpipe_call_details_finalization_retrying, ^finalizer, :database_unavailable}

    assert_receive {:publication_timer_scheduled, ^finalizer, token, 5_000}

    Agent.update(source, &Map.put(&1, :response, {:ok, assessment(:complete)}))
    send(finalizer, {:vxpipe_publication_timer, token})

    assert_receive {:vxpipe_call_details_finalization_submitted, ^finalizer, worker, :started,
                    :complete}

    assert_receive {:vxpipe_call_details_published, ^worker, _publication_id, 1}
  end

  test "stops cleanly when a refresh reaches a missing or still-live call" do
    for terminal_reason <- [:call_not_found, :call_not_ended] do
      observer = self()
      clock = start_agent(fn -> ~U[2026-09-12 18:00:10.000Z] end)
      repository = repository(observer)
      source = source_agent(observer, {:error, terminal_reason})

      assert {:ok, finalizer, :started} =
               Vxpipe.Calls.finalize_call_details(
                 @tenant_key,
                 @call_id <> Atom.to_string(terminal_reason),
                 options(observer, repository, source, clock)
               )

      monitor = Process.monitor(finalizer)

      assert_receive {:vxpipe_call_details_finalization_skipped, ^finalizer, ^terminal_reason}
      assert_receive {:DOWN, ^monitor, :process, ^finalizer, :normal}
      refute_receive {:publication_timer_scheduled, ^finalizer, _token, _delay}
    end
  end

  defp options(observer, repository, source, clock) do
    finalizer_supervisor =
      start_supervised!(
        {DynamicSupervisor, strategy: :one_for_one},
        id: make_ref()
      )

    [
      publication_source: {TestPublicationSource, %{observer: observer, response: source}},
      publication_repository: {TestPublicationRepository, repository},
      publication_artifact_writer:
        {TestPublicationArtifactWriter,
         %{observer: observer, response: :success, published_at: @published_at}},
      publication_clock: {TestPublicationClock, clock},
      publication_timer: {TestPublicationTimer, observer},
      publication_finalizer_supervisor: finalizer_supervisor,
      settlement_poll_ms: 5_000,
      observer: observer
    ]
  end

  defp repository(observer) do
    start_agent(fn -> %{observer: observer, publications: %{}} end)
  end

  defp source_agent(observer, response) do
    start_agent(fn -> %{observer: observer, response: response} end)
  end

  defp start_agent(fun), do: start_supervised!({Agent, fun}, id: make_ref())

  defp assessment(status) do
    assert {:ok, component} = PublicationComponent.new("history", status)
    assert {:ok, source} = CallDetailsSource.new(source_attributes())
    assert {:ok, assessment} = CallDetailsAssessment.new(@ended_at, source, [component])
    assessment
  end

  defp source_attributes do
    [
      call: %{
        "identity" => %{
          "call_id" => @call_id,
          "tenant_key" => @tenant_key,
          "definition_id" => "support",
          "definition_revision" => 3,
          "definition_schema_version" => "20260908.01",
          "plan_digest" => "sha256:0123456789abcdef"
        },
        "lifecycle" => %{
          "state" => "ended",
          "direction" => "inbound",
          "route" => %{"service" => "web", "participant" => "caller"},
          "created_at" => "2026-09-12T17:59:00.000Z",
          "started_at" => "2026-09-12T17:59:05.000Z",
          "ended_at" => "2026-09-12T18:00:00.000Z",
          "terminal_reason" => "normal"
        }
      },
      participants: [],
      transcript: [],
      tools: [],
      transfers: [],
      usage: %{"amounts" => [], "observations" => [], "totals" => []},
      variables: %{"latest_revision" => 0, "sections" => %{}},
      artifacts: []
    ]
  end
end
