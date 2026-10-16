defmodule Vxpipe.Persistence.Repo.Migrations.CreateOauthRateLimits do
  use Ecto.Migration

  def change do
    create table(:oauth_rate_limits, primary_key: false) do
      add(:operation, :string, primary_key: true)
      add(:bucket, :string, primary_key: true)
      add(:identity_digest, :binary, primary_key: true)
      add(:window_start, :bigint, primary_key: true)
      add(:attempts, :bigint, null: false)
    end

    create(index(:oauth_rate_limits, [:operation, :window_start]))
  end
end
