defmodule Vxpipe.Persistence.CallDetailsPublicationRecord do
  @moduledoc false

  alias Vxpipe.Calls.CallDetailsPublication
  alias Vxpipe.Persistence.Schema.Call
  alias Vxpipe.Persistence.Schema.CallDetailsPublication, as: StoredPublication

  @spec reserve_changeset(Call.t(), CallDetailsPublication.t()) :: Ecto.Changeset.t()
  def reserve_changeset(call, publication) do
    StoredPublication.reserve_changeset(%StoredPublication{}, %{
      public_id: publication.id,
      call_id: call.id,
      schema_version: publication.schema_version,
      source_digest: publication.source_digest,
      recorded_at: publication.recorded_at,
      filename: publication.filename,
      completeness: publication.completeness,
      checksum: publication.checksum,
      contents: publication.contents,
      status: publication.status
    })
  end

  @spec decode(StoredPublication.t(), String.t(), String.t()) ::
          {:ok, CallDetailsPublication.t()} | {:error, :invalid_call_details_publication}
  def decode(stored, tenant_key, call_id) do
    CallDetailsPublication.new(
      id: stored.public_id,
      tenant_key: tenant_key,
      call_id: call_id,
      schema_version: stored.schema_version,
      source_digest: stored.source_digest,
      recorded_at: stored.recorded_at,
      filename: stored.filename,
      completeness: stored.completeness,
      checksum: stored.checksum,
      contents: stored.contents,
      status: stored.status,
      object_key: stored.object_key,
      object_reference: stored.object_reference,
      published_at: stored.published_at
    )
  end
end
