defmodule Vxpipe.Persistence.CallDetailsPublicationStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    CallDetailsObject,
    CallDetailsSnapshot,
    CallDetailsSource,
    PublicationComponent,
    PublicationDecision,
    PublicationWindow
  }

  alias Vxpipe.Persistence.{CallDetailsPublicationStore, Repo}

  alias Vxpipe.Persistence.Schema.{
    Call,
    CallDefinition,
    CallDetailsPublication,
    DefinitionRevision,
    Tenant
  }

  @tenant_key "PUBLICATIONTEN01"
  @call_id "11111111-2222-4333-8444-555555555555"
  @room_id "66666666-7777-4888-8999-000000000000"
  @ended_at ~U[2026-09-12 16:00:00.000000Z]

  setup do
    call = insert_ended_call()
    options = [publication_repository: {CallDetailsPublicationStore, Repo}]
    [call: call, options: options]
  end

  test "reserves immutable revisions, deduplicates a source, and never regresses latest",
       context do
    older = snapshot("publication-old", ~U[2026-09-12 16:01:00.100Z], 1)

    assert {:ok, old_record, :created} =
             Calls.reserve_call_details(@tenant_key, @call_id, older, context.options)

    assert old_record.status == :pending
    assert old_record.contents == older.contents
    assert old_record.filename == "details-20260912160100100.json"
    assert old_record.object_key == nil
    assert old_record.object_reference == nil
    assert old_record.published_at == nil
    refute inspect(old_record) =~ "Hello revision 1"

    retry = snapshot("publication-retry", ~U[2026-09-12 16:01:01.200Z], 1)

    assert {:ok, duplicate, :existing} =
             Calls.reserve_call_details(@tenant_key, @call_id, retry, context.options)

    assert duplicate.id == old_record.id
    assert duplicate.recorded_at == old_record.recorded_at
    assert duplicate.filename == old_record.filename
    assert duplicate.contents == old_record.contents
    assert Repo.aggregate(CallDetailsPublication, :count) == 1

    newer = snapshot("publication-new", ~U[2026-09-12 16:01:02.300Z], 2)

    assert {:ok, new_record, :created} =
             Calls.reserve_call_details(@tenant_key, @call_id, newer, context.options)

    assert Repo.aggregate(CallDetailsPublication, :count) == 2

    assert {:ok, published_new} =
             Calls.mark_call_details_published(
               @tenant_key,
               @call_id,
               new_record.id,
               object(new_record, "etag-new", ~U[2026-09-12 16:01:03.000Z]),
               context.options
             )

    assert published_new.status == :published
    assert latest_publication_id() == new_record.id

    assert {:ok, published_old} =
             Calls.mark_call_details_published(
               @tenant_key,
               @call_id,
               old_record.id,
               object(old_record, "etag-old", ~U[2026-09-12 16:01:04.000Z]),
               context.options
             )

    assert published_old.status == :published
    assert latest_publication_id() == new_record.id

    assert {:ok, ^published_old} =
             Calls.mark_call_details_published(
               @tenant_key,
               @call_id,
               old_record.id,
               object(old_record, "etag-old", ~U[2026-09-12 16:01:04.000Z]),
               context.options
             )

    persisted_call = Repo.get!(Call, context.call.id)
    assert persisted_call.ended_at == @ended_at
    assert persisted_call.state == :ended
  end

  test "rejects filename collisions and conflicting publication receipts", context do
    recorded_at = ~U[2026-09-12 16:01:00.100Z]
    first = snapshot("publication-first", recorded_at, 1)
    collision = snapshot("publication-collision", recorded_at, 2)

    results =
      [first, collision]
      |> Task.async_stream(
        &Calls.reserve_call_details(@tenant_key, @call_id, &1, context.options),
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _publication, :created}, &1)) == 1
    assert Enum.count(results, &match?({:error, :publication_filename_conflict}, &1)) == 1

    first_record =
      Enum.find_value(results, fn
        {:ok, publication, :created} -> publication
        _other -> nil
      end)

    receipt = object(first_record, "etag-first", ~U[2026-09-12 16:01:03.000Z])

    assert {:ok, _published} =
             Calls.mark_call_details_published(
               @tenant_key,
               @call_id,
               first_record.id,
               receipt,
               context.options
             )

    conflicting = object(first_record, "etag-different", ~U[2026-09-12 16:01:03.000Z])

    assert {:error, :publication_receipt_conflict} =
             Calls.mark_call_details_published(
               @tenant_key,
               @call_id,
               first_record.id,
               conflicting,
               context.options
             )

    assert {:error, :publication_not_found} =
             Calls.mark_call_details_published(
               @tenant_key,
               @call_id,
               "publication-missing",
               receipt,
               context.options
             )

    assert Repo.aggregate(CallDetailsPublication, :count) == 1
  end

  test "does not reserve publications for live, foreign-tenant, or deleted calls", context do
    assert {1, nil} =
             Repo.update_all(
               from(call in Call, where: call.id == ^context.call.id),
               set: [state: :running, ended_at: nil]
             )

    candidate = snapshot("publication-live", ~U[2026-09-12 16:01:00.100Z], 1)

    assert {:error, :call_not_ended} =
             Calls.reserve_call_details(@tenant_key, @call_id, candidate, context.options)

    assert {:error, :call_not_found} =
             Calls.reserve_call_details("OTHERPUBLICATION", @call_id, candidate, context.options)

    Repo.delete!(Repo.get!(Call, context.call.id))

    assert {:error, :call_not_found} =
             Calls.reserve_call_details(@tenant_key, @call_id, candidate, context.options)

    assert Repo.aggregate(CallDetailsPublication, :count) == 0
  end

  test "deleting the owning call removes pending and published revisions", context do
    pending = snapshot("publication-pending", ~U[2026-09-12 16:01:00.100Z], 1)
    published = snapshot("publication-published", ~U[2026-09-12 16:01:01.200Z], 2)

    assert {:ok, _pending_record, :created} =
             Calls.reserve_call_details(@tenant_key, @call_id, pending, context.options)

    assert {:ok, published_record, :created} =
             Calls.reserve_call_details(@tenant_key, @call_id, published, context.options)

    assert {:ok, _published_record} =
             Calls.mark_call_details_published(
               @tenant_key,
               @call_id,
               published_record.id,
               object(published_record, "etag-published", ~U[2026-09-12 16:01:02.000Z]),
               context.options
             )

    Repo.delete!(Repo.get!(Call, context.call.id))

    assert Repo.aggregate(CallDetailsPublication, :count) == 0
  end

  test "lists bounded pending revisions oldest first with public call ownership", context do
    oldest = snapshot("publication-oldest", ~U[2026-09-12 16:01:00.100Z], 1)
    published = snapshot("publication-delivered", ~U[2026-09-12 16:01:01.200Z], 2)
    newest = snapshot("publication-newest", ~U[2026-09-12 16:01:02.300Z], 3)

    assert {:ok, oldest_record, :created} =
             Calls.reserve_call_details(@tenant_key, @call_id, oldest, context.options)

    assert {:ok, published_record, :created} =
             Calls.reserve_call_details(@tenant_key, @call_id, published, context.options)

    assert {:ok, _newest_record, :created} =
             Calls.reserve_call_details(@tenant_key, @call_id, newest, context.options)

    assert {:ok, _published_record} =
             Calls.mark_call_details_published(
               @tenant_key,
               @call_id,
               published_record.id,
               object(published_record, "etag-published", ~U[2026-09-12 16:01:03.000Z]),
               context.options
             )

    assert {:ok, [pending]} = Calls.list_pending_call_details(1, context.options)
    assert pending.id == oldest_record.id
    assert pending.tenant_key == @tenant_key
    assert pending.call_id == @call_id
    assert pending.status == :pending
  end

  defp snapshot(id, recorded_at, variable_revision) do
    assert {:ok, history} = PublicationComponent.new("history", :complete)
    assert {:ok, usage} = PublicationComponent.new("usage", :complete)

    assert {:ok, %PublicationDecision{} = decision} =
             PublicationWindow.evaluate(
               @ended_at,
               DateTime.add(@ended_at, 1, :second),
               [history, usage]
             )

    assert {:ok, source} =
             CallDetailsSource.new(
               call: %{
                 "identity" => %{
                   "call_id" => @call_id,
                   "tenant_key" => @tenant_key,
                   "definition_id" => "publication-definition",
                   "definition_revision" => 1,
                   "definition_schema_version" => "20260912.01",
                   "plan_digest" => "sha256:publication-plan"
                 },
                 "lifecycle" => %{
                   "state" => "ended",
                   "direction" => "inbound",
                   "route" => %{"service" => "web"},
                   "created_at" => "2026-09-12T15:59:00.000Z",
                   "started_at" => "2026-09-12T15:59:05.000Z",
                   "ended_at" => "2026-09-12T16:00:00.000Z",
                   "terminal_reason" => "normal"
                 }
               },
               participants: [],
               transcript: [
                 %{"speaker" => "caller", "text" => "Hello revision #{variable_revision}"}
               ],
               tools: [],
               transfers: [],
               usage: %{"amounts" => [], "observations" => [], "totals" => []},
               variables: %{"latest_revision" => variable_revision, "sections" => %{}},
               artifacts: []
             )

    assert {:ok, snapshot} = CallDetailsSnapshot.new(id, recorded_at, source, decision)
    snapshot
  end

  defp object(record, etag, published_at) do
    object_key = "calls/publication/#{@call_id}/#{record.filename}"

    assert {:ok, object} =
             CallDetailsObject.new(
               object_key,
               %{"object_key" => object_key, "etag" => etag},
               published_at
             )

    object
  end

  defp latest_publication_id do
    call = Call |> Repo.get_by!(public_id: @call_id) |> Repo.preload(:latest_details_publication)
    call.latest_details_publication.public_id
  end

  defp insert_ended_call do
    tenant =
      %Tenant{}
      |> Tenant.changeset(%{key: @tenant_key, name: "Publication tenant"})
      |> Repo.insert!()

    definition =
      %CallDefinition{}
      |> CallDefinition.changeset(%{tenant_id: tenant.id, public_id: "publication-definition"})
      |> Repo.insert!()

    revision =
      %DefinitionRevision{}
      |> DefinitionRevision.changeset(%{
        call_definition_id: definition.id,
        revision: 1,
        schema_version: "20260912.01",
        source: %{},
        source_digest: String.duplicate("a", 64),
        compiled_metadata: %{},
        validation_errors: []
      })
      |> Repo.insert!()

    %Call{}
    |> Call.changeset(%{
      public_id: @call_id,
      tenant_id: tenant.id,
      definition_revision_id: revision.id,
      participant_routes: %{},
      entry_caller: "caller",
      entry_receiver: "assistant",
      initial_variables: %{},
      resolved_plan: :erlang.term_to_binary(%{}),
      plan_digest: :crypto.hash(:sha256, "publication-plan"),
      state: :ended,
      room_id: @room_id,
      incarnation_id: "rinc-publication",
      created_at: DateTime.add(@ended_at, -60, :second),
      started_at: DateTime.add(@ended_at, -55, :second),
      ended_at: @ended_at
    })
    |> Repo.insert!()
  end
end
