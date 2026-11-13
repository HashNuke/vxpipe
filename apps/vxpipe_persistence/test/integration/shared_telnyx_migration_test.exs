defmodule Vxpipe.Persistence.Integration.SharedTelnyxMigrationTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @child_dir Path.expand("../..", __DIR__)

  test "populated migration preserves dedicated bindings and published service references" do
    database = "vxpipe_telnyx_migration_#{System.unique_integer([:positive])}"
    command!("createdb", [database])
    on_exit(fn -> command!("dropdb", ["--if-exists", database]) end)
    migrate(database, ["--to-exclusive", "20261113111500"])

    query(database, """
    INSERT INTO tenants (key, name, inserted_at, updated_at)
      VALUES ('ExistingTenant01', 'Existing tenant', now(), now());
    INSERT INTO telephony_services (public_id, tenant_id, name, ingress_key, provider,
      provider_connection_id, credential_name, answering_machine_detection,
      media_token_ttl_ms, webhook_tolerance_seconds, inserted_at, updated_at)
      SELECT gen_random_uuid(), id, 'support', 'migration-support', 'telnyx',
        'dedicated-existing', 'telnyx', 'disabled', 60000, 300, now(), now() FROM tenants;
    INSERT INTO call_specs (tenant_id, inserted_at, updated_at) SELECT id, now(), now() FROM tenants;
    INSERT INTO call_spec_revisions (call_spec_id, revision, schema_version, source,
      source_digest, compiled_metadata, validation_errors, inserted_at)
      SELECT id, 1, '20260915.01', '{}', repeat('a', 64), '{}', '{}', now() FROM call_specs;
    INSERT INTO telephony_routes (tenant_id, call_spec_revision_id, participant_ref,
      service, number, published_at, inserted_at, updated_at)
      SELECT t.id, v.id, 'caller', 'support', '+15550001000', now(), now(), now()
      FROM tenants t CROSS JOIN call_spec_revisions v;
    UPDATE call_specs SET published_revision_id = (SELECT id FROM call_spec_revisions), published_at = now();
    """)

    before =
      query(
        database,
        "SELECT public_id || ':' || name || ':' || provider_connection_id FROM telephony_services"
      )

    migrate(database, [])

    assert query(
             database,
             "SELECT public_id || ':' || name || ':' || provider_connection_id FROM telephony_services"
           ) == before

    assert query(
             database,
             "SELECT count(*) FROM telephony_routes r JOIN call_spec_revisions v ON v.id = r.call_spec_revision_id JOIN call_specs s ON s.published_revision_id = v.id WHERE r.service = 'support' AND r.published_at IS NOT NULL"
           ) == "1"

    assert query(
             database,
             "SELECT count(*) FROM telnyx_settings WHERE id = 1 AND application_id IS NULL"
           ) == "1"

    query(database, """
    INSERT INTO telephony_services (public_id, tenant_id, name, ingress_key, provider,
      provider_connection_id, credential_name, answering_machine_detection,
      media_token_ttl_ms, webhook_tolerance_seconds, inserted_at, updated_at)
      SELECT gen_random_uuid(), id, names.name, 'migration-' || names.name, 'telnyx',
        NULL, 'telnyx', 'disabled', 60000, 300, now(), now()
      FROM tenants CROSS JOIN unnest(ARRAY['inherited-one', 'inherited-two']) AS names(name);
    """)

    assert query(
             database,
             "SELECT count(*) FROM telephony_services WHERE provider_connection_id IS NULL"
           ) == "2"

    assert query(
             database,
             "SELECT count(*) FROM pg_indexes WHERE indexname IN ('telephony_services_scoped_application_index', 'telephony_legs_telnyx_application_event_index', 'telephony_legs_telnyx_application_leg_index')"
           ) == "3"
  end

  defp migrate(database, options),
    do:
      command!("mix", ["ecto.migrate", "--quiet" | options],
        cd: @child_dir,
        env: [
          {"MIX_ENV", "test"},
          {"VXPIPE_TEST_DATABASE_URL", nil},
          {"VXPIPE_TEST_DATABASE", database}
        ]
      )

  defp query(database, sql),
    do:
      command!("psql", ["-X", "-v", "ON_ERROR_STOP=1", "-d", database, "-Atqc", sql])
      |> String.trim()

  defp command!(program, args, options \\ []) do
    case System.cmd(program, args, Keyword.put(options, :stderr_to_stdout, true)) do
      {output, 0} -> output
      {output, status} -> flunk("#{program} failed (#{status}): #{output}")
    end
  end
end
