defmodule Vxpipe.Persistence.CallHangupStore do
  @moduledoc "Call-row-locked cancellation intent, without runtime or token-row side effects."

  import Ecto.Query
  alias Vxpipe.Persistence.PreparedCallRecord
  alias Vxpipe.Persistence.Schema.{Admission, Call}

  def request(repo, tenant, id, %DateTime{} = now) do
    case Ecto.UUID.cast(id) do
      {:ok, ^id} -> request_locked(repo, tenant, id, now)
      _invalid_or_noncanonical -> {:error, :not_found}
    end
  end

  def request(_repo, _tenant, _id, _now), do: {:error, :invalid_call_hangup}

  defp request_locked(repo, tenant, id, now) do
    repo.transaction(fn ->
      query =
        from(call in Call,
          join: tenant in assoc(call, :tenant),
          join: revision in assoc(call, :call_spec_revision),
          join: specification in assoc(revision, :call_spec),
          where: tenant.key == ^tenant and call.public_id == ^id,
          lock: "FOR UPDATE OF c0",
          select: {call, {tenant, specification, revision}}
        )

      with {call, selection} <- repo.one(query),
           true <- DateTime.compare(now, call.created_at) != :lt,
           {:ok, changed} <- persist_intent(repo, call, now),
           {:ok, result} <- PreparedCallRecord.load(changed, selection) do
        result
      else
        nil -> repo.rollback(:not_found)
        false -> repo.rollback(:invalid_call_hangup)
        {:error, _reason} -> repo.rollback(:call_hangup_unavailable)
      end
    end)
  end

  defp persist_intent(_repo, %Call{state: :ended} = call, _now), do: {:ok, call}

  defp persist_intent(_repo, %Call{hangup_requested_at: %DateTime{}} = call, _now),
    do: {:ok, call}

  defp persist_intent(repo, call, now) do
    prepared_unclaimed? =
      call.state == :prepared and is_nil(call.started_at) and
        is_nil(call.incarnation_id) and
        not repo.exists?(from(admission in Admission, where: admission.call_id == ^call.id))

    call |> Call.hangup_changeset(now, prepared_unclaimed?) |> repo.update()
  end
end
