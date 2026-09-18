defmodule Vxpipe.Persistence.Repo.Migrations.RenameDefinitionsToCallSpecs do
  use Ecto.Migration

  def up do
    rename table(:call_definitions), to: table(:call_specs)
    rename table(:definition_revisions), to: table(:call_spec_revisions)

    rename table(:call_spec_revisions), :call_definition_id, to: :call_spec_id
    rename table(:calls), :definition_revision_id, to: :call_spec_revision_id
    rename table(:participant_routes), :definition_revision_id, to: :call_spec_revision_id
    rename table(:telephony_routes), :definition_revision_id, to: :call_spec_revision_id

    rename_index(:call_definitions_tenant_id_public_id_index,
      :call_specs_tenant_id_public_id_index
    )

    rename_index(
      :definition_revisions_call_definition_id_revision_index,
      :call_spec_revisions_call_spec_id_revision_index
    )

    rename_index(:call_definitions_published_revision_id_index, :call_specs_published_revision_id_index)

    rename_index(
      :calls_definition_revision_id_index,
      :calls_call_spec_revision_id_index
    )

    rename_index(
      :participant_routes_definition_revision_id_participant_ref_index,
      :participant_routes_call_spec_revision_id_participant_ref_index
    )

    rename_index(
      :telephony_routes_definition_revision_id_participant_ref_index,
      :telephony_routes_call_spec_revision_id_participant_ref_index
    )

    rename_sequence(:call_definitions_id_seq, :call_specs_id_seq)
    rename_sequence(:definition_revisions_id_seq, :call_spec_revisions_id_seq)

    rename_constraint(:call_specs, :call_definitions_pkey, :call_specs_pkey)
    rename_constraint(:call_spec_revisions, :definition_revisions_pkey, :call_spec_revisions_pkey)

    rename_constraint(
      :call_specs,
      :call_definitions_tenant_id_fkey,
      :call_specs_tenant_id_fkey
    )

    rename_constraint(
      :call_spec_revisions,
      :definition_revisions_call_definition_id_fkey,
      :call_spec_revisions_call_spec_id_fkey
    )

    rename_constraint(
      :call_specs,
      :call_definitions_published_revision_id_fkey,
      :call_specs_published_revision_id_fkey
    )

    rename_constraint(
      :calls,
      :calls_definition_revision_id_fkey,
      :calls_call_spec_revision_id_fkey
    )

    rename_constraint(
      :participant_routes,
      :participant_routes_definition_revision_id_fkey,
      :participant_routes_call_spec_revision_id_fkey
    )

    rename_constraint(
      :telephony_routes,
      :telephony_routes_definition_revision_id_fkey,
      :telephony_routes_call_spec_revision_id_fkey
    )
  end

  def down do
    rename_constraint(
      :telephony_routes,
      :telephony_routes_call_spec_revision_id_fkey,
      :telephony_routes_definition_revision_id_fkey
    )

    rename_constraint(
      :participant_routes,
      :participant_routes_call_spec_revision_id_fkey,
      :participant_routes_definition_revision_id_fkey
    )

    rename_constraint(
      :calls,
      :calls_call_spec_revision_id_fkey,
      :calls_definition_revision_id_fkey
    )

    rename_constraint(
      :call_specs,
      :call_specs_published_revision_id_fkey,
      :call_definitions_published_revision_id_fkey
    )

    rename_constraint(
      :call_spec_revisions,
      :call_spec_revisions_call_spec_id_fkey,
      :definition_revisions_call_definition_id_fkey
    )

    rename_constraint(
      :call_specs,
      :call_specs_tenant_id_fkey,
      :call_definitions_tenant_id_fkey
    )

    rename_constraint(:call_spec_revisions, :call_spec_revisions_pkey, :definition_revisions_pkey)
    rename_constraint(:call_specs, :call_specs_pkey, :call_definitions_pkey)

    rename_sequence(:call_spec_revisions_id_seq, :definition_revisions_id_seq)
    rename_sequence(:call_specs_id_seq, :call_definitions_id_seq)

    rename_index(:telephony_routes_call_spec_revision_id_participant_ref_index,
      :telephony_routes_definition_revision_id_participant_ref_index
    )

    rename_index(:participant_routes_call_spec_revision_id_participant_ref_index,
      :participant_routes_definition_revision_id_participant_ref_index
    )

    rename_index(:calls_call_spec_revision_id_index, :calls_definition_revision_id_index)
    rename_index(:call_specs_published_revision_id_index, :call_definitions_published_revision_id_index)

    rename_index(
      :call_spec_revisions_call_spec_id_revision_index,
      :definition_revisions_call_definition_id_revision_index
    )

    rename_index(:call_specs_tenant_id_public_id_index, :call_definitions_tenant_id_public_id_index)

    rename table(:telephony_routes), :call_spec_revision_id, to: :definition_revision_id
    rename table(:participant_routes), :call_spec_revision_id, to: :definition_revision_id
    rename table(:calls), :call_spec_revision_id, to: :definition_revision_id
    rename table(:call_spec_revisions), :call_spec_id, to: :call_definition_id
    rename table(:call_spec_revisions), to: table(:definition_revisions)
    rename table(:call_specs), to: table(:call_definitions)
  end

  defp rename_index(from, to) do
    execute("ALTER INDEX #{from} RENAME TO #{to}", "ALTER INDEX #{to} RENAME TO #{from}")
  end

  defp rename_constraint(table, from, to) do
    execute(
      "ALTER TABLE #{table} RENAME CONSTRAINT #{from} TO #{to}",
      "ALTER TABLE #{table} RENAME CONSTRAINT #{to} TO #{from}"
    )
  end

  defp rename_sequence(from, to) do
    execute("ALTER SEQUENCE #{from} RENAME TO #{to}", "ALTER SEQUENCE #{to} RENAME TO #{from}")
  end
end
