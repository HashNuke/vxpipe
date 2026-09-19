defmodule Vxpipe.Persistence.Repo.Migrations.AddEffectiveTelnyxBindings do
  use Ecto.Migration

  def up do
    alter table(:telephony_services) do
      add(:credential_name, :string)
      modify(:credential_id, :uuid, null: true)
    end

    drop(constraint(:telephony_services, :telephony_services_provider_public_key))

    create(
      constraint(:telephony_services, :telephony_services_credential_binding,
        check:
          "(credential_name IS NULL AND credential_id IS NOT NULL) OR (provider = 'telnyx' AND credential_name IS NOT NULL AND credential_name = 'telnyx' AND credential_id IS NULL AND public_key IS NULL)"
      )
    )

    create(
      constraint(:telephony_services, :telephony_services_provider_public_key,
        check:
          "(provider = 'telnyx' AND (credential_name IS NOT NULL OR public_key IS NOT NULL)) OR (provider = 'twilio' AND public_key IS NULL AND credential_name IS NULL)"
      )
    )

    create(
      unique_index(:telephony_services, [:provider_connection_id],
        where: "credential_name IS NOT NULL",
        name: :telephony_services_scoped_application_index
      )
    )
  end

  def down do
    execute("""
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM telephony_services WHERE credential_name IS NOT NULL) THEN
        RAISE EXCEPTION 'Scoped Telnyx bindings require explicit cutover before rollback';
      END IF;
    END $$;
    """)

    drop(
      index(:telephony_services, [:provider_connection_id],
        name: :telephony_services_scoped_application_index
      )
    )

    drop(constraint(:telephony_services, :telephony_services_credential_binding))
    drop(constraint(:telephony_services, :telephony_services_provider_public_key))

    create(
      constraint(:telephony_services, :telephony_services_provider_public_key,
        check:
          "(provider = 'telnyx' AND public_key IS NOT NULL) OR (provider = 'twilio' AND public_key IS NULL)"
      )
    )

    alter table(:telephony_services) do
      remove(:credential_name)
      modify(:credential_id, :uuid, null: false)
    end
  end
end
