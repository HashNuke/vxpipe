defmodule Vxpipe.Calls.PublicationWorkerTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Calls.{
    CallDetailsObject,
    CallDetailsSnapshot,
    CallDetailsSource,
    PublicationComponent,
    PublicationDecision,
    PublicationWindow,
    TestPublicationArtifactWriter,
    TestPublicationRepository
  }

  @tenant_key "TENANT001"
  @call_id "call-publication-worker"
  @ended_at ~U[2026-09-12 16:00:00.000Z]
  @recorded_at ~U[2026-09-12 16:01:00.100Z]
  @published_at ~U[2026-09-12 16:01:02.000Z]

  test "publishes a reserved snapshot asynchronously outside its caller" do
    observer = self()

    repository =
      start_supervised!({Agent, fn -> %{observer: observer, publications: %{}} end})

    options = [
      publication_repository: {TestPublicationRepository, repository},
      publication_artifact_writer:
        {TestPublicationArtifactWriter,
         %{observer: observer, response: :success, published_at: @published_at}},
      observer: observer
    ]

    assert {:ok, worker, :started} =
             Vxpipe.Calls.publish_call_details(
               @tenant_key,
               @call_id,
               snapshot(),
               options
             )

    monitor = Process.monitor(worker)

    assert_receive {:publication_reserved, attempt, @tenant_key, @call_id}
    assert attempt != self()
    assert_receive {:publication_write_started, ^attempt, "publication-worker-1"}

    assert_receive {:publication_committed, ^attempt, @tenant_key, @call_id,
                    "publication-worker-1"}

    assert_receive {:vxpipe_call_details_published, ^worker, "publication-worker-1", 1}
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}

    assert {:ok, retry, :started} =
             Vxpipe.Calls.publish_call_details(@tenant_key, @call_id, snapshot(), options)

    assert_receive {:publication_reserved, _retry_attempt, @tenant_key, @call_id}
    assert_receive {:vxpipe_call_details_published, ^retry, "publication-worker-1", 1}
    refute_receive {:publication_write_started, _retry_attempt, "publication-worker-1"}
  end

  test "bounds retries and leaves the reserved publication pending after storage failure" do
    observer = self()
    repository = repository(observer)
    snapshot = snapshot()

    assert {:ok, worker, :started} =
             Vxpipe.Calls.publish_call_details(
               @tenant_key,
               @call_id,
               snapshot,
               publication_repository: {TestPublicationRepository, repository},
               publication_artifact_writer:
                 {TestPublicationArtifactWriter,
                  %{
                    observer: observer,
                    response: {:error, :storage_unavailable},
                    published_at: @published_at
                  }},
               maximum_attempts: 2,
               retry_delay_ms: 0,
               observer: observer
             )

    monitor = Process.monitor(worker)

    assert_receive {:vxpipe_call_details_retrying, ^worker, "publication-worker-1", 1,
                    :storage_unavailable}

    assert_receive {:vxpipe_call_details_unavailable, ^worker, "publication-worker-1", 2,
                    :storage_unavailable}

    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}

    assert [publication] =
             repository
             |> TestPublicationRepository.publications()
             |> Map.values()

    assert publication.source_digest == snapshot.source_digest
    assert publication.status == :pending

    assert_received {:publication_write_started, _first_attempt, "publication-worker-1"}
    assert_received {:publication_write_started, _second_attempt, "publication-worker-1"}
    refute_received {:publication_committed, _, _, _, _}
  end

  test "terminates a blocked attempt at its configured deadline" do
    observer = self()
    repository = repository(observer)
    release_reference = make_ref()

    assert {:ok, worker, :started} =
             Vxpipe.Calls.publish_call_details(
               @tenant_key,
               @call_id,
               snapshot(),
               publication_repository: {TestPublicationRepository, repository},
               publication_artifact_writer:
                 {TestPublicationArtifactWriter,
                  %{
                    observer: observer,
                    response: {:wait, release_reference},
                    published_at: @published_at
                  }},
               maximum_attempts: 1,
               attempt_timeout_ms: 20,
               observer: observer
             )

    worker_monitor = Process.monitor(worker)
    assert_receive {:publication_write_started, attempt, "publication-worker-1"}
    attempt_monitor = Process.monitor(attempt)

    assert_receive {:vxpipe_call_details_unavailable, ^worker, "publication-worker-1", 1,
                    :publication_attempt_timeout}

    assert_receive {:DOWN, ^attempt_monitor, :process, ^attempt, :killed}
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :normal}
    refute_received {:publication_committed, _, _, _, _}
  end

  test "coalesces the same active source into one worker" do
    observer = self()
    repository = repository(observer)
    release_reference = make_ref()
    snapshot = snapshot()

    options = [
      publication_repository: {TestPublicationRepository, repository},
      publication_artifact_writer:
        {TestPublicationArtifactWriter,
         %{
           observer: observer,
           response: {:wait, release_reference},
           published_at: @published_at
         }},
      observer: observer
    ]

    assert {:ok, worker, :started} =
             Vxpipe.Calls.publish_call_details(@tenant_key, @call_id, snapshot, options)

    assert_receive {:publication_write_started, attempt, "publication-worker-1"}

    assert {:ok, ^worker, :existing} =
             Vxpipe.Calls.publish_call_details(@tenant_key, @call_id, snapshot, options)

    assert {:ok, object} = published_object(snapshot)
    send(attempt, {:release_publication_write, release_reference, {:ok, object}})

    assert_receive {:vxpipe_call_details_published, ^worker, "publication-worker-1", 1}
    refute_receive {:publication_write_started, _other_attempt, "publication-worker-1"}
  end

  defp snapshot do
    assert {:ok, component} = PublicationComponent.new("history", :complete)

    assert {:ok, %PublicationDecision{} = decision} =
             PublicationWindow.evaluate(@ended_at, @recorded_at, [component])

    assert {:ok, source} = CallDetailsSource.new(source_attributes())

    assert {:ok, snapshot} =
             CallDetailsSnapshot.new("publication-worker-1", @recorded_at, source, decision)

    snapshot
  end

  defp repository(observer) do
    start_supervised!({Agent, fn -> %{observer: observer, publications: %{}} end})
  end

  defp published_object(snapshot) do
    object_key = "calls/test/details/#{snapshot.filename}"

    CallDetailsObject.new(
      object_key,
      %{"object_key" => object_key, "etag" => "test-etag"},
      @published_at
    )
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
          "created_at" => "2026-09-12T15:59:00.000Z",
          "started_at" => "2026-09-12T15:59:05.000Z",
          "ended_at" => "2026-09-12T16:00:00.000Z",
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
