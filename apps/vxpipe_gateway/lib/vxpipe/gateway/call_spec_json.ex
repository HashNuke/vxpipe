defmodule Vxpipe.Gateway.CallSpecJSON do
  @moduledoc "Public call-spec projections shared by product adapters."

  alias Vxpipe.Calls.{CallSpecErrors, CallSpecPage, CallSpecRevision}

  def page(%CallSpecPage{} = page) do
    %{
      tenant: %{key: page.tenant.key, name: page.tenant.name},
      call_specs: Enum.map(page.call_specs, &summary/1),
      pagination: %{
        page: page.page,
        page_size: page.page_size,
        total: page.total,
        total_pages: page.total_pages
      }
    }
  end

  def read(%{call_spec: stored, latest_revision: latest, published_revision: published}) do
    %{
      call_spec:
        Map.merge(revision(stored), %{latest_revision: latest, published_revision: published})
    }
  end

  def revision(%CallSpecRevision{} = revision),
    do: Map.put(write_revision(revision), :source, revision.source)

  def write_revision(%CallSpecRevision{} = revision) do
    %{
      call_spec_id: revision.call_spec_id,
      revision: revision.revision,
      schema_version: revision.schema_version,
      source_digest: revision.source_digest,
      published: not is_nil(revision.published_at),
      published_at: if(revision.published_at, do: DateTime.to_iso8601(revision.published_at)),
      validation_errors: CallSpecErrors.validation_errors(revision.validation_errors),
      routes:
        Enum.map(
          revision.routes,
          &%{
            participant_key: &1.key,
            participant_ref: &1.participant_ref,
            published: not is_nil(&1.published_at)
          }
        )
    }
  end

  defp summary(spec) do
    %{
      id: spec.id,
      name: spec.name,
      latest_revision: spec.latest_revision,
      published_revision: spec.published_revision,
      call_count: spec.call_count,
      updated_at: DateTime.to_iso8601(spec.updated_at)
    }
  end
end
