defmodule Vxpipe.Calls.CallDetailsPublicationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{
    CallDetailsSnapshot,
    CallDetailsSource,
    CallDetailsObject,
    PublicationComponent,
    PublicationDecision,
    PublicationWindow
  }

  @ended_at ~U[2026-09-08 12:34:00.000Z]

  test "publishes a settled call early and preserves intentional absences" do
    components = [
      component("history", :complete),
      component("usage", :complete),
      component("recording", :prohibited, %{"policy" => "record_audio_disabled"}),
      component("offline_mix", :unconfigured),
      component("summary", :not_produced)
    ]

    assert {:ok,
            %PublicationDecision{
              action: :publish,
              completeness: :complete,
              pending_components: [],
              incomplete_components: []
            } = decision} =
             PublicationWindow.evaluate(
               @ended_at,
               ~U[2026-09-08 12:34:01.000Z],
               components
             )

    assert {:ok, source} = CallDetailsSource.new(source_attributes())

    assert {:ok, snapshot} =
             CallDetailsSnapshot.new(
               "publication-1",
               ~U[2026-09-08 12:34:56.789Z],
               source,
               decision
             )

    assert snapshot.filename == "details-20260908123456789.json"
    assert snapshot.completeness == :complete
    assert byte_size(snapshot.checksum) == 32
    assert byte_size(snapshot.source_digest) == 32

    document = JSON.decode!(snapshot.contents)

    assert document["schema_version"] == "20260912.01"
    assert document["publication"]["id"] == "publication-1"
    assert document["publication"]["recorded_at"] == "2026-09-08T12:34:56.789Z"
    assert document["publication"]["completeness"] == "complete"

    assert document["publication"]["components"]["recording"] == %{
             "details" => %{"policy" => "record_audio_disabled"},
             "status" => "prohibited"
           }

    assert document["call"]["identity"]["call_id"] == "call-1"
    assert document["call"]["lifecycle"]["ended_at"] == "2026-09-08T12:34:00.000Z"
    assert document["transcript"] == [%{"speaker" => "caller", "text" => "Hello"}]
  end

  test "waits for pending work before the deadline, then publishes it as incomplete" do
    components = [component("history", :complete), component("usage", :pending)]

    assert {:ok, %PublicationDecision{action: :wait}} =
             PublicationWindow.evaluate(@ended_at, @ended_at, components)

    assert {:ok,
            %PublicationDecision{
              action: :wait,
              completeness: :incomplete,
              pending_components: ["usage"],
              incomplete_components: ["usage"],
              deadline: ~U[2026-09-08 12:35:00.000Z]
            }} =
             PublicationWindow.evaluate(
               @ended_at,
               ~U[2026-09-08 12:34:59.999Z],
               components
             )

    assert {:ok,
            %PublicationDecision{
              action: :publish,
              completeness: :incomplete,
              pending_components: ["usage"],
              incomplete_components: ["usage"]
            }} =
             PublicationWindow.evaluate(
               @ended_at,
               ~U[2026-09-08 12:35:00.000Z],
               components
             )
  end

  test "publishes known failure or missing evidence early without calling it complete" do
    components = [
      component("history", :missing, %{"missing_sequences" => [2]}),
      component("usage", :failed, %{"reason" => "storage_unavailable"}),
      component("recording", :not_produced)
    ]

    assert {:ok,
            %PublicationDecision{
              action: :publish,
              completeness: :incomplete,
              pending_components: [],
              incomplete_components: ["history", "usage"]
            }} =
             PublicationWindow.evaluate(
               @ended_at,
               ~U[2026-09-08 12:34:01.000Z],
               components
             )
  end

  test "canonical snapshot bytes and source digest do not depend on map insertion order" do
    components = [component("history", :complete)]

    assert {:ok, decision} =
             PublicationWindow.evaluate(
               @ended_at,
               ~U[2026-09-08 12:34:01.000Z],
               components
             )

    attributes = source_attributes()
    reversed_call = attributes |> Keyword.fetch!(:call) |> Enum.reverse() |> Map.new()

    assert {:ok, source_a} = CallDetailsSource.new(attributes)
    assert {:ok, source_b} = CallDetailsSource.new(Keyword.put(attributes, :call, reversed_call))

    recorded_at = ~U[2026-09-08 12:34:56.789Z]

    assert {:ok, snapshot_a} =
             CallDetailsSnapshot.new("publication-1", recorded_at, source_a, decision)

    assert {:ok, snapshot_b} =
             CallDetailsSnapshot.new("publication-1", recorded_at, source_b, decision)

    assert snapshot_a.contents == snapshot_b.contents
    assert snapshot_a.checksum == snapshot_b.checksum
    assert snapshot_a.source_digest == snapshot_b.source_digest
  end

  test "rejects a publication record timestamp that is not UTC" do
    components = [component("history", :complete)]

    assert {:ok, decision} =
             PublicationWindow.evaluate(
               @ended_at,
               ~U[2026-09-08 12:34:01.000Z],
               components
             )

    assert {:ok, source} = CallDetailsSource.new(source_attributes())

    non_utc = %{
      ~U[2026-09-08 12:34:56.789Z]
      | utc_offset: 3_600,
        zone_abbr: "+01",
        time_zone: "+01"
    }

    assert {:error, :invalid_call_details_snapshot} =
             CallDetailsSnapshot.new("publication-1", non_utc, source, decision)
  end

  test "rejects non-JSON component details at the component boundary" do
    assert {:error, :invalid_component} =
             PublicationComponent.new("usage", :failed, %{"worker" => self()})
  end

  test "rejects a bearer URL where a protected object key is required" do
    signed_url = "https://objects.example.test/details.json?signature=test-only"

    assert {:error, :invalid_call_details_object} =
             CallDetailsObject.new(
               signed_url,
               %{"object_key" => signed_url},
               ~U[2026-09-08 12:34:56.789Z]
             )
  end

  defp component(name, status, details \\ %{}) do
    assert {:ok, component} = PublicationComponent.new(name, status, details)
    component
  end

  defp source_attributes do
    [
      call: %{
        "identity" => %{
          "call_id" => "call-1",
          "tenant_key" => "TENANT001",
          "call_spec_id" => "support",
          "call_spec_revision" => 3,
          "call_spec_schema_version" => "20260908.01",
          "plan_digest" => "sha256:0123456789abcdef"
        },
        "lifecycle" => %{
          "state" => "ended",
          "direction" => "inbound",
          "route" => %{"service" => "web", "participant" => "caller"},
          "created_at" => "2026-09-08T12:33:00.000Z",
          "started_at" => "2026-09-08T12:33:05.000Z",
          "ended_at" => "2026-09-08T12:34:00.000Z",
          "terminal_reason" => "normal"
        }
      },
      participants: [%{"id" => "caller", "type" => "human"}],
      transcript: [%{"speaker" => "caller", "text" => "Hello"}],
      tools: [],
      transfers: [],
      usage: %{"amounts" => [], "observations" => [], "totals" => []},
      variables: %{"latest_revision" => 1, "sections" => %{"order" => %{"id" => "42"}}},
      artifacts: []
    ]
  end
end
