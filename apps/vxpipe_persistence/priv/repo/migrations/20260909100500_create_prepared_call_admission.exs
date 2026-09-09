defmodule Vxpipe.Persistence.Repo.Migrations.CreatePreparedCallAdmission do
  use Ecto.Migration

  def change do
    create table(:calls) do
      add :public_id, :uuid, null: false
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false

      add :definition_revision_id,
          references(:definition_revisions, on_delete: :restrict),
          null: false

      add :participant_routes, :map, null: false
      add :entry_caller, :string, null: false
      add :entry_receiver, :string, null: false
      add :initial_variables, :map, null: false
      add :resolved_plan, :binary, null: false
      add :plan_digest, :binary, null: false
      add :state, :string, null: false
      add :room_id, :uuid, null: false
      add :created_at, :utc_datetime_usec, null: false
      add :started_at, :utc_datetime_usec
      add :ended_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:calls, [:public_id])
    create unique_index(:calls, [:tenant_id, :public_id])
    create index(:calls, [:tenant_id, :state])
    create index(:calls, [:definition_revision_id])
    create constraint(:calls, :calls_plan_digest_size, check: "octet_length(plan_digest) = 32")

    create constraint(:calls, :calls_state,
             check: "state IN ('prepared', 'admitting', 'running', 'ended', 'failed')"
           )

    create table(:join_tokens) do
      add :public_id, :uuid, null: false
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :call_id, references(:calls, on_delete: :delete_all), null: false
      add :participant_key, :uuid, null: false
      add :participant_ref, :string, null: false
      add :digest, :binary, null: false
      add :issued_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:join_tokens, [:public_id])
    create unique_index(:join_tokens, [:digest])
    create index(:join_tokens, [:tenant_id, :call_id, :participant_key])
    create index(:join_tokens, [:expires_at, :consumed_at])
    create constraint(:join_tokens, :join_tokens_digest_size, check: "octet_length(digest) = 32")

    create constraint(:join_tokens, :join_tokens_expiry_order,
             check: "expires_at > issued_at"
           )

    create table(:call_admissions) do
      add :call_id, references(:calls, on_delete: :delete_all), null: false
      add :join_token_id, references(:join_tokens, on_delete: :restrict), null: false
      add :participant_key, :uuid, null: false
      add :participant_ref, :string, null: false
      add :accepted_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:call_admissions, [:join_token_id])
    create unique_index(:call_admissions, [:call_id, :participant_ref])
  end
end
