defmodule Vxpipe.Persistence.CallDetailsPublicationPending do
  @moduledoc false

  import Ecto.Query

  alias Vxpipe.Persistence.CallDetailsPublicationRecord
  alias Vxpipe.Persistence.Schema.{Call, Tenant}
  alias Vxpipe.Persistence.Schema.CallDetailsPublication, as: StoredPublication

  @spec list(module(), pos_integer()) ::
          {:ok, [Vxpipe.Calls.CallDetailsPublication.t()]} | {:error, term()}
  def list(repo, limit) do
    query =
      from(publication in StoredPublication,
        join: call in Call,
        on: call.id == publication.call_id,
        join: tenant in Tenant,
        on: tenant.id == call.tenant_id,
        where: publication.status == :pending,
        order_by: [asc: publication.recorded_at, asc: publication.id],
        limit: ^limit,
        select: {publication, tenant.key, call.public_id}
      )

    query
    |> repo.all()
    |> decode()
  end

  defp decode(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn {stored, tenant_key, call_id}, {:ok, publications} ->
      case CallDetailsPublicationRecord.decode(stored, tenant_key, call_id) do
        {:ok, publication} -> {:cont, {:ok, [publication | publications]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, publications} -> {:ok, Enum.reverse(publications)}
      {:error, reason} -> {:error, reason}
    end
  end
end
