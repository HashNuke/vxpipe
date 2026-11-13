defmodule Vxpipe.Persistence.TelnyxRouting do
  @moduledoc false
  import Ecto.Query

  alias Vxpipe.Persistence.Schema.{TelephonyRoute, TelephonyService, TelnyxSettings}

  # Take this before service/credential locks. Readers coexist with publication;
  # configuration waits for both. Publication serializes shared-number checks.
  def lock(repo, mode) do
    query = from(s in TelnyxSettings, where: s.id == 1)

    query =
      case mode do
        :read -> from(s in query, lock: "FOR KEY SHARE")
        :publish -> from(s in query, lock: "FOR NO KEY UPDATE")
        :write -> from(s in query, lock: "FOR UPDATE")
      end

    repo.one!(query, log: false, telemetry_event: nil)
  end

  def validate_default(_repo, nil), do: :ok

  def validate_default(repo, id) do
    conflict? =
      repo.exists?(
        from(s in TelephonyService,
          where:
            s.provider == "telnyx" and s.credential_name == "telnyx" and
              s.provider_connection_id == ^id
        )
      )

    if conflict?, do: {:error, :telephony_service_conflict}, else: :ok
  end

  def validate_application(repo, %{provider: "telnyx", credential_name: "telnyx"} = service) do
    case service.provider_connection_id do
      nil ->
        numbers =
          from(r in published_routes(),
            join: t in assoc(r, :tenant),
            where: t.key == ^service.tenant_key and r.service == ^service.name,
            select: r.number
          )

        conflict? =
          repo.exists?(
            from([r, s] in shared_routes(),
              where: s.public_id != ^service.id and r.number in subquery(numbers)
            )
          )

        if conflict?, do: {:error, :phone_number_in_use}, else: :ok

      id ->
        if repo.get!(TelnyxSettings, 1).application_id == id,
          do: {:error, :telephony_service_conflict},
          else: :ok
    end
  end

  def validate_application(_repo, _service), do: :ok

  def publication_conflict?(repo, call_spec, revision) do
    numbers =
      from(r in TelephonyRoute,
        join: s in TelephonyService,
        on: s.tenant_id == r.tenant_id and s.name == r.service,
        where:
          r.call_spec_revision_id == ^revision.id and s.provider == "telnyx" and
            s.credential_name == "telnyx" and is_nil(s.provider_connection_id),
        select: r.number
      )

    repo.exists?(
      from([r, _service, _revision, spec] in shared_routes(),
        where: spec.id != ^call_spec.id and r.number in subquery(numbers)
      )
    )
  end

  defp shared_routes do
    from(r in TelephonyRoute,
      join: s in TelephonyService,
      on: s.tenant_id == r.tenant_id and s.name == r.service,
      join: v in assoc(r, :call_spec_revision),
      join: spec in assoc(v, :call_spec),
      where:
        s.provider == "telnyx" and s.credential_name == "telnyx" and
          is_nil(s.provider_connection_id) and not is_nil(r.published_at) and
          spec.published_revision_id == v.id
    )
  end

  defp published_routes do
    from(r in TelephonyRoute,
      join: v in assoc(r, :call_spec_revision),
      join: s in assoc(v, :call_spec),
      where: not is_nil(r.published_at) and s.published_revision_id == v.id
    )
  end
end
