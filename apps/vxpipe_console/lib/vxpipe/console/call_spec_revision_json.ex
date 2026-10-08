defmodule Vxpipe.Console.CallSpecRevisionJSON do
  @moduledoc false
  alias Vxpipe.Calls.CallSpecErrors

  def render(revision) do
    %{
      call_spec_id: revision.call_spec_id,
      revision: revision.revision,
      schema_version: revision.schema_version,
      source: revision.source,
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
end
