defmodule Vxpipe.Persistence.CallSpecPublicationConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Persistence.{Repo, CallSpecStore}
  alias Vxpipe.Persistence.Schema.{CallSpec, CallSpecRevision, CallSpecPublication, Tenant}

  test "independent publication transactions serialize duplicate requests and version allocation" do
    {tenant, spec, revisions} =
      Sandbox.unboxed_run(Repo, fn ->
        tenant =
          Repo.insert!(
            Tenant.changeset(%Tenant{}, %{
              key: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false),
              name: "Publication concurrency"
            })
          )

        spec = Repo.insert!(CallSpec.changeset(%CallSpec{}, %{tenant_id: tenant.id}))

        revisions =
          for number <- 1..3 do
            Repo.insert!(
              CallSpecRevision.changeset(%CallSpecRevision{}, %{
                call_spec_id: spec.id,
                revision: number,
                schema_version: "20261004.01",
                source: %{"name" => "Source #{number}"},
                source_digest: String.duplicate("a", 64),
                compiled_metadata: %{},
                validation_errors: []
              })
            )
          end

        {tenant, spec, revisions}
      end)

    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> Repo.delete!(tenant) end) end)
    id = Integer.to_string(spec.id)

    publish = fn revision ->
      Sandbox.unboxed_run(Repo, fn ->
        CallSpecStore.publish_revision(Repo, tenant.key, id, revision, DateTime.utc_now())
      end)
    end

    duplicates = Task.async_stream([1, 1], publish, max_concurrency: 2, timeout: 15_000) |> Enum.to_list()
    assert length(duplicates) == 2
    for result <- duplicates do
      assert {:ok, {:ok, publication}} = result
      assert publication.publication.version == 1
    end

    results =
      Task.async_stream([2, 3], publish, max_concurrency: 2, timeout: 15_000) |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1))

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.all(
               from(p in CallSpecPublication,
                 where: p.call_spec_id == ^spec.id,
                 order_by: p.version,
                 select: p.version
               )
             ) == [1, 2, 3]

      assert Repo.get!(CallSpec, spec.id).published_version == 3

      assert Enum.map(revisions, &Repo.get!(CallSpecRevision, &1.id).source) ==
               Enum.map(revisions, & &1.source)
    end)
  end
end
