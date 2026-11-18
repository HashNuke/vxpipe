defmodule Vxpipe.Persistence.CallSpecPublications do
  @moduledoc "One-statement publication status and bounded history for a tenant-checked spec."
  import Ecto.Query
  alias Vxpipe.Persistence.Schema.{CallSpec, CallSpecPublication, CallSpecRevision}

  def read(repo, call_spec_id) do
    latest =
      from(r in CallSpecRevision,
        where: r.call_spec_id == ^call_spec_id,
        order_by: [desc: r.revision],
        limit: 1
      )

    rows =
      repo.all(
        from(s in CallSpec,
          join: draft in subquery(latest),
          on: draft.call_spec_id == s.id,
          left_join: live in CallSpecRevision,
          on: live.id == s.published_revision_id,
          left_join: event in CallSpecPublication,
          on: event.call_spec_id == s.id and event.version <= s.published_version,
          where: s.id == ^call_spec_id,
          order_by: [desc: event.version],
          limit: 3,
          select:
            {s.published_version, live.revision,
             fragment("? IS DISTINCT FROM ?", draft.source, live.source), draft.inserted_at,
             event.version, event.published_at}
        )
      )

    [{version, revision, changes, saved_at, _, _} | _] = rows

    %{
      version: version,
      revision: revision,
      unpublished_changes: changes,
      draft_saved_at: saved_at,
      history:
        for(
          {_, _, _, _, number, date} <- rows,
          not is_nil(number),
          do: %{version: number, published_at: date}
        )
    }
  end
end
