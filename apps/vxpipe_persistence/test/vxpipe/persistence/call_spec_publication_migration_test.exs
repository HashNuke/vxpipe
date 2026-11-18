defmodule Vxpipe.Persistence.CallSpecPublicationMigrationTest do
  use Vxpipe.Persistence.DataCase, async: false

  @migration Path.expand(
               "../../../priv/repo/migrations/20261117152000_add_call_spec_publications.exs",
               __DIR__
             )
  Code.require_file(@migration)
  alias Vxpipe.Persistence.Repo.Migrations.AddCallSpecPublications

  test "migration retains only the known live version/date and is reversible without changing source IDs" do
    Repo.query!(
      "CREATE TEMP TABLE call_specs (id bigserial PRIMARY KEY, published_revision_id bigint, published_at timestamp(6)) ON COMMIT DROP"
    )

    Repo.query!(
      "CREATE TEMP TABLE call_spec_revisions (id bigserial PRIMARY KEY, revision integer NOT NULL) ON COMMIT DROP"
    )

    Repo.query!("INSERT INTO call_spec_revisions (id, revision) VALUES (91, 6), (92, 7), (93, 1)")

    Repo.query!(
      "INSERT INTO call_specs (id, published_revision_id, published_at) VALUES (1, 91, '2026-11-16 10:30:00'), (2, NULL, NULL)"
    )

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      20_261_117_152_000,
      AddCallSpecPublications,
      :forward,
      :up,
      :up, prefix: "pg_temp", log: false)

    assert %{rows: [[1, 91, 6, ~N[2026-11-16 10:30:00.000000]]]} =
             Repo.query!(
               "SELECT call_spec_id, call_spec_revision_id, version, published_at FROM pg_temp.call_spec_publications"
             )

    assert %{rows: [[1, 6], [2, nil]]} =
             Repo.query!("SELECT id, published_version FROM pg_temp.call_specs ORDER BY id")

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      20_261_117_152_000,
      AddCallSpecPublications,
      :forward,
      :down,
      :down, prefix: "pg_temp", log: false)

    assert %{rows: [[91, 6], [92, 7], [93, 1]]} =
             Repo.query!("SELECT id, revision FROM pg_temp.call_spec_revisions ORDER BY id")
  end
end
