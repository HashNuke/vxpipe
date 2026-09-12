defmodule Vxpipe.Calls.CallDetailsFinalizationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Calls.{
    CallDetailsAssessment,
    CallDetailsSource,
    PublicationComponent,
    PublicationDecision,
    TestPublicationArtifactWriter,
    TestPublicationRepository,
    TestPublicationSource
  }

  @tenant_key "TENANT001"
  @call_id "call-finalization"
  @ended_at ~U[2026-09-12 17:00:00.000Z]
  @published_at ~U[2026-09-12 17:01:02.000Z]

  setup do
    observer = self()

    repository =
      start_supervised!({Agent, fn -> %{observer: observer, publications: %{}} end})

    common = [
      publication_repository: {TestPublicationRepository, repository},
      publication_artifact_writer:
        {TestPublicationArtifactWriter,
         %{observer: observer, response: :success, published_at: @published_at}},
      observer: observer
    ]

    [repository: repository, common: common]
  end

  test "waits for an unsettled component before the reporting deadline", context do
    assessment = assessment(1, [component("history", :complete), component("usage", :pending)])

    options =
      Keyword.put(
        context.common,
        :publication_source,
        {TestPublicationSource, %{observer: self(), response: {:ok, assessment}}}
      )

    assert {:wait,
            %PublicationDecision{
              action: :wait,
              deadline: ~U[2026-09-12 17:01:00.000Z],
              pending_components: ["usage"]
            }} =
             Vxpipe.Calls.assess_call_details(
               @tenant_key,
               @call_id,
               ~U[2026-09-12 17:00:30.000Z],
               options
             )

    assert_receive {:publication_source_read, source_reader, @tenant_key, @call_id}
    assert source_reader == self()
    refute_received {:publication_reserved, _, _, _}
  end

  test "publishes available facts as incomplete at the deadline", context do
    assessment = assessment(1, [component("history", :complete), component("usage", :pending)])

    options =
      context.common
      |> Keyword.put(
        :publication_source,
        {TestPublicationSource, %{observer: self(), response: {:ok, assessment}}}
      )
      |> Keyword.put(:publication_id, "publication-deadline")

    assert {:publish, %PublicationDecision{action: :publish, completeness: :incomplete}, snapshot,
            worker, :started} =
             Vxpipe.Calls.assess_call_details(
               @tenant_key,
               @call_id,
               ~U[2026-09-12 17:01:00.000Z],
               options
             )

    assert snapshot.publication_id == "publication-deadline"
    assert snapshot.recorded_at == ~U[2026-09-12 17:01:00.000Z]
    assert snapshot.completeness == :incomplete
    assert_receive {:vxpipe_call_details_published, ^worker, "publication-deadline", 1}
  end

  test "changed late facts produce another immutable source revision", context do
    complete_components = [component("history", :complete), component("usage", :complete)]

    first =
      context.common
      |> Keyword.put(
        :publication_source,
        {TestPublicationSource,
         %{observer: self(), response: {:ok, assessment(1, complete_components)}}}
      )
      |> Keyword.put(:publication_id, "publication-first")

    assert {:publish, _decision, first_snapshot, first_worker, :started} =
             Vxpipe.Calls.assess_call_details(
               @tenant_key,
               @call_id,
               ~U[2026-09-12 17:00:10.000Z],
               first
             )

    first_monitor = Process.monitor(first_worker)
    assert_receive {:vxpipe_call_details_published, ^first_worker, "publication-first", 1}
    assert_receive {:DOWN, ^first_monitor, :process, ^first_worker, :normal}

    second =
      context.common
      |> Keyword.put(
        :publication_source,
        {TestPublicationSource,
         %{observer: self(), response: {:ok, assessment(2, complete_components)}}}
      )
      |> Keyword.put(:publication_id, "publication-second")

    assert {:publish, _decision, second_snapshot, second_worker, :started} =
             Vxpipe.Calls.assess_call_details(
               @tenant_key,
               @call_id,
               ~U[2026-09-12 17:00:11.000Z],
               second
             )

    assert first_snapshot.source_digest != second_snapshot.source_digest
    assert first_snapshot.filename != second_snapshot.filename
    assert_receive {:vxpipe_call_details_published, ^second_worker, "publication-second", 1}
    assert map_size(TestPublicationRepository.publications(context.repository)) == 2
  end

  defp assessment(variable_revision, components) do
    assert {:ok, source} = CallDetailsSource.new(source_attributes(variable_revision))
    assert {:ok, assessment} = CallDetailsAssessment.new(@ended_at, source, components)
    assessment
  end

  defp component(name, status) do
    assert {:ok, component} = PublicationComponent.new(name, status)
    component
  end

  defp source_attributes(variable_revision) do
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
          "created_at" => "2026-09-12T16:59:00.000Z",
          "started_at" => "2026-09-12T16:59:05.000Z",
          "ended_at" => "2026-09-12T17:00:00.000Z",
          "terminal_reason" => "normal"
        }
      },
      participants: [],
      transcript: [],
      tools: [],
      transfers: [],
      usage: %{"amounts" => [], "observations" => [], "totals" => []},
      variables: %{"latest_revision" => variable_revision, "sections" => %{}},
      artifacts: []
    ]
  end
end
