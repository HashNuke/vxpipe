defmodule Vxpipe.Persistence.CallSpecMigrationTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Persistence.Repo

  @migration_module Vxpipe.Persistence.Repo.Migrations.RenameDefinitionsToCallSpecs
  @migration_version 20_260_918_130_000
  @repo_name :call_spec_migration_test_repo

  test "renames the call-spec graph without losing rows, constraints, or sequences" do
    ensure_migration_module_loaded()
    schema = "call_spec_migration_#{System.unique_integer([:positive])}"

    # The migration contains unqualified raw ALTER statements. Keep its dedicated
    # connection on the generated schema's search_path without touching public.
    start_supervised!({Repo, name: @repo_name, pool: DBConnection.ConnectionPool, pool_size: 1})

    try do
      create_legacy_schema(@repo_name, schema)

      assert :ok = migrate(@repo_name, schema, :up)

      assert %Postgrex.Result{rows: [[20, 10, 30]]} =
               query!(
                 @repo_name,
                 "SELECT id, tenant_id, published_revision_id FROM call_specs ORDER BY id"
               )

      assert %Postgrex.Result{rows: [[30, 20, 1]]} =
               query!(
                 @repo_name,
                 "SELECT id, call_spec_id, revision FROM call_spec_revisions ORDER BY id"
               )

      assert %Postgrex.Result{rows: [[40, 30]]} =
               query!(@repo_name, "SELECT id, call_spec_revision_id FROM calls WHERE id = 40")

      assert %Postgrex.Result{rows: [[50, 30], [60, 30]]} =
               query!(
                 @repo_name,
                 "SELECT id, call_spec_revision_id FROM participant_routes WHERE id = 50 " <>
                   "UNION ALL SELECT id, call_spec_revision_id FROM telephony_routes WHERE id = 60 " <>
                   "ORDER BY id"
               )

      assert foreign_keys(@repo_name, schema) == [
               {"call_spec_revisions_call_spec_id_fkey", "call_spec_revisions", "call_specs"},
               {"call_specs_published_revision_id_fkey", "call_specs", "call_spec_revisions"},
               {"call_specs_tenant_id_fkey", "call_specs", "tenants"},
               {"calls_call_spec_revision_id_fkey", "calls", "call_spec_revisions"},
               {"participant_routes_call_spec_revision_id_fkey", "participant_routes",
                "call_spec_revisions"},
               {"telephony_routes_call_spec_revision_id_fkey", "telephony_routes",
                "call_spec_revisions"}
             ]

      assert index_names(@repo_name, schema) == [
               "call_spec_revisions_call_spec_id_revision_index",
               "call_spec_revisions_pkey",
               "call_specs_pkey",
               "call_specs_published_revision_id_index",
               "call_specs_tenant_id_public_id_index",
               "calls_call_spec_revision_id_index",
               "calls_pkey",
               "participant_routes_call_spec_revision_id_participant_ref_index",
               "participant_routes_pkey",
               "telephony_routes_call_spec_revision_id_participant_ref_index",
               "telephony_routes_pkey",
               "tenants_pkey"
             ]

      assert sequence_exists?(@repo_name, schema, "call_specs_id_seq")
      assert sequence_exists?(@repo_name, schema, "call_spec_revisions_id_seq")
      refute sequence_exists?(@repo_name, schema, "call_definitions_id_seq")
      refute sequence_exists?(@repo_name, schema, "definition_revisions_id_seq")

      assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
               query(
                 @repo_name,
                 "INSERT INTO call_specs (tenant_id, public_id) VALUES (10, 'legacy-spec')"
               )

      assert 22 = insert_call_spec(@repo_name, "after-first-up")
      assert 31 = insert_call_spec_revision(@repo_name, 20, 2)

      assert :ok = migrate(@repo_name, schema, :down)

      assert %Postgrex.Result{rows: [[20, 10, 30], [22, 10, nil]]} =
               query!(
                 @repo_name,
                 "SELECT id, tenant_id, published_revision_id FROM call_definitions ORDER BY id"
               )

      assert %Postgrex.Result{rows: [[30, 20, 1], [31, 20, 2]]} =
               query!(
                 @repo_name,
                 "SELECT id, call_definition_id, revision FROM definition_revisions ORDER BY id"
               )

      assert %Postgrex.Result{rows: [[40, 30]]} =
               query!(@repo_name, "SELECT id, definition_revision_id FROM calls WHERE id = 40")

      assert %Postgrex.Result{rows: [[50, 30], [60, 30]]} =
               query!(
                 @repo_name,
                 "SELECT id, definition_revision_id FROM participant_routes WHERE id = 50 " <>
                   "UNION ALL SELECT id, definition_revision_id FROM telephony_routes WHERE id = 60 " <>
                   "ORDER BY id"
               )

      assert foreign_keys(@repo_name, schema) == [
               {"call_definitions_published_revision_id_fkey", "call_definitions",
                "definition_revisions"},
               {"call_definitions_tenant_id_fkey", "call_definitions", "tenants"},
               {"calls_definition_revision_id_fkey", "calls", "definition_revisions"},
               {"definition_revisions_call_definition_id_fkey", "definition_revisions",
                "call_definitions"},
               {"participant_routes_definition_revision_id_fkey", "participant_routes",
                "definition_revisions"},
               {"telephony_routes_definition_revision_id_fkey", "telephony_routes",
                "definition_revisions"}
             ]

      assert index_names(@repo_name, schema) == [
               "call_definitions_pkey",
               "call_definitions_published_revision_id_index",
               "call_definitions_tenant_id_public_id_index",
               "calls_definition_revision_id_index",
               "calls_pkey",
               "definition_revisions_call_definition_id_revision_index",
               "definition_revisions_pkey",
               "participant_routes_definition_revision_id_participant_ref_index",
               "participant_routes_pkey",
               "telephony_routes_definition_revision_id_participant_ref_index",
               "telephony_routes_pkey",
               "tenants_pkey"
             ]

      assert sequence_exists?(@repo_name, schema, "call_definitions_id_seq")
      assert sequence_exists?(@repo_name, schema, "definition_revisions_id_seq")

      assert :ok = migrate(@repo_name, schema, :up)
      assert 23 = insert_call_spec(@repo_name, "after-round-trip")
      assert 32 = insert_call_spec_revision(@repo_name, 20, 3)

      assert %Postgrex.Result{rows: [[40, 30]]} =
               query!(@repo_name, "SELECT id, call_spec_revision_id FROM calls WHERE id = 40")

      assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
               query(
                 @repo_name,
                 "INSERT INTO call_specs (tenant_id, public_id) VALUES (10, 'legacy-spec')"
               )
    after
      query!(@repo_name, "DROP SCHEMA IF EXISTS #{schema} CASCADE")
    end
  end

  defp ensure_migration_module_loaded do
    unless Code.ensure_loaded?(@migration_module) do
      Code.require_file(
        Application.app_dir(
          :vxpipe_persistence,
          "priv/repo/migrations/20260918130000_rename_definitions_to_call_specs.exs"
        )
      )
    end
  end

  defp create_legacy_schema(repo_name, schema) do
    query!(repo_name, "CREATE SCHEMA #{schema}")
    query!(repo_name, "SET search_path TO #{schema}, public")

    [
      """
      CREATE TABLE tenants (
        id bigint PRIMARY KEY
      )
      """,
      """
      CREATE TABLE call_definitions (
        id bigserial PRIMARY KEY,
        tenant_id bigint NOT NULL,
        public_id text NOT NULL,
        published_revision_id bigint,
        CONSTRAINT call_definitions_tenant_id_fkey
          FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
      )
      """,
      """
      CREATE TABLE definition_revisions (
        id bigserial PRIMARY KEY,
        call_definition_id bigint NOT NULL,
        revision integer NOT NULL,
        CONSTRAINT definition_revisions_call_definition_id_fkey
          FOREIGN KEY (call_definition_id) REFERENCES call_definitions(id) ON DELETE CASCADE
      )
      """,
      """
      ALTER TABLE call_definitions
      ADD CONSTRAINT call_definitions_published_revision_id_fkey
      FOREIGN KEY (published_revision_id) REFERENCES definition_revisions(id) ON DELETE SET NULL
      """,
      """
      CREATE TABLE calls (
        id bigserial PRIMARY KEY,
        tenant_id bigint NOT NULL,
        public_id text NOT NULL,
        definition_revision_id bigint NOT NULL,
        CONSTRAINT calls_definition_revision_id_fkey
          FOREIGN KEY (definition_revision_id) REFERENCES definition_revisions(id) ON DELETE RESTRICT
      )
      """,
      """
      CREATE TABLE participant_routes (
        id bigserial PRIMARY KEY,
        public_id text NOT NULL,
        tenant_id bigint NOT NULL,
        definition_revision_id bigint NOT NULL,
        participant_ref text NOT NULL,
        CONSTRAINT participant_routes_definition_revision_id_fkey
          FOREIGN KEY (definition_revision_id) REFERENCES definition_revisions(id) ON DELETE CASCADE
      )
      """,
      """
      CREATE TABLE telephony_routes (
        id bigserial PRIMARY KEY,
        tenant_id bigint NOT NULL,
        definition_revision_id bigint NOT NULL,
        participant_ref text NOT NULL,
        CONSTRAINT telephony_routes_definition_revision_id_fkey
          FOREIGN KEY (definition_revision_id) REFERENCES definition_revisions(id) ON DELETE CASCADE
      )
      """,
      "CREATE UNIQUE INDEX call_definitions_tenant_id_public_id_index ON call_definitions (tenant_id, public_id)",
      "CREATE UNIQUE INDEX definition_revisions_call_definition_id_revision_index ON definition_revisions (call_definition_id, revision)",
      "CREATE INDEX call_definitions_published_revision_id_index ON call_definitions (published_revision_id)",
      "CREATE INDEX calls_definition_revision_id_index ON calls (definition_revision_id)",
      "CREATE UNIQUE INDEX participant_routes_definition_revision_id_participant_ref_index ON participant_routes (definition_revision_id, participant_ref)",
      "CREATE UNIQUE INDEX telephony_routes_definition_revision_id_participant_ref_index ON telephony_routes (definition_revision_id, participant_ref)"
    ]
    |> Enum.each(&query!(repo_name, &1))

    query!(repo_name, "INSERT INTO tenants (id) VALUES (10)")

    query!(
      repo_name,
      "INSERT INTO call_definitions (id, tenant_id, public_id) VALUES (20, 10, 'legacy-spec')"
    )

    query!(
      repo_name,
      "INSERT INTO definition_revisions (id, call_definition_id, revision) VALUES (30, 20, 1)"
    )

    query!(repo_name, "UPDATE call_definitions SET published_revision_id = 30 WHERE id = 20")

    query!(
      repo_name,
      "INSERT INTO calls (id, tenant_id, public_id, definition_revision_id) VALUES (40, 10, 'call-40', 30)"
    )

    query!(
      repo_name,
      "INSERT INTO participant_routes (id, public_id, tenant_id, definition_revision_id, participant_ref) VALUES (50, 'route-50', 10, 30, 'caller')"
    )

    query!(
      repo_name,
      "INSERT INTO telephony_routes (id, tenant_id, definition_revision_id, participant_ref) VALUES (60, 10, 30, 'caller')"
    )

    query!(repo_name, "SELECT setval('call_definitions_id_seq', 20, true)")
    query!(repo_name, "SELECT setval('definition_revisions_id_seq', 30, true)")
  end

  defp migrate(repo_name, schema, direction) do
    options = [
      dynamic_repo: repo_name,
      migration_lock: false,
      prefix: schema,
      log: false,
      log_migrator_sql: false
    ]

    case direction do
      :up -> Ecto.Migrator.up(Repo, @migration_version, @migration_module, options)
      :down -> Ecto.Migrator.down(Repo, @migration_version, @migration_module, options)
    end
  end

  defp insert_call_spec(repo_name, public_id) do
    %Postgrex.Result{rows: [[id]]} =
      query!(
        repo_name,
        "INSERT INTO call_specs (tenant_id, public_id) VALUES (10, $1) RETURNING id",
        [public_id]
      )

    id
  end

  defp insert_call_spec_revision(repo_name, call_spec_id, revision) do
    %Postgrex.Result{rows: [[id]]} =
      query!(
        repo_name,
        "INSERT INTO call_spec_revisions (call_spec_id, revision) VALUES ($1, $2) RETURNING id",
        [call_spec_id, revision]
      )

    id
  end

  defp foreign_keys(repo_name, schema) do
    %Postgrex.Result{rows: rows} =
      query!(
        repo_name,
        """
        SELECT constraint_name, table_name, referenced_table_name
        FROM (
          SELECT
            c.conname AS constraint_name,
            rel.relname AS table_name,
            referenced.relname AS referenced_table_name,
            rel_namespace.nspname AS table_schema
          FROM pg_constraint AS c
          JOIN pg_class AS rel ON rel.oid = c.conrelid
          JOIN pg_namespace AS rel_namespace ON rel_namespace.oid = rel.relnamespace
          JOIN pg_class AS referenced ON referenced.oid = c.confrelid
          WHERE c.contype = 'f'
        ) AS foreign_keys
        WHERE table_schema = $1
        ORDER BY constraint_name
        """,
        [schema]
      )

    Enum.map(rows, fn [constraint_name, table_name, referenced_table_name] ->
      {constraint_name, table_name, referenced_table_name}
    end)
  end

  defp index_names(repo_name, schema) do
    %Postgrex.Result{rows: rows} =
      query!(
        repo_name,
        """
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = $1 AND tablename <> 'schema_migrations'
        ORDER BY indexname
        """,
        [schema]
      )

    Enum.map(rows, fn [index_name] -> index_name end)
  end

  defp sequence_exists?(repo_name, schema, sequence_name) do
    %Postgrex.Result{rows: [[exists]]} =
      query!(
        repo_name,
        """
        SELECT EXISTS(
          SELECT 1
          FROM pg_class AS sequences
          JOIN pg_namespace AS namespaces ON namespaces.oid = sequences.relnamespace
          WHERE sequences.relkind = 'S'
            AND sequences.relname = $1
            AND namespaces.nspname = $2
        )
        """,
        [sequence_name, schema]
      )

    exists
  end

  defp query!(repo_name, sql, params \\ []) do
    previous_repo = Repo.put_dynamic_repo(repo_name)

    try do
      Repo.query!(sql, params)
    after
      Repo.put_dynamic_repo(previous_repo)
    end
  end

  defp query(repo_name, sql, params \\ []) do
    previous_repo = Repo.put_dynamic_repo(repo_name)

    try do
      Repo.query(sql, params)
    after
      Repo.put_dynamic_repo(previous_repo)
    end
  end
end
