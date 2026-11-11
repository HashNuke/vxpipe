defmodule Vxpipe.Persistence.OAuth.Clients do
  @moduledoc "Resolves external client identifiers to durable OAuth clients and refreshes CIMD on authorization."
  import Ecto.Query
  alias Vxpipe.Identity.OAuth.Profile
  alias Vxpipe.Persistence.OAuth.{Client, ClientMetadata, Retention, Transaction}
  alias Vxpipe.Persistence.Repo

  def find(identifier, lock \\ nil) do
    query =
      if Profile.metadata_url?(identifier) do
        from(c in Client, where: c.metadata_url == ^identifier)
      else
        from(c in Client, where: c.public_id == ^identifier and is_nil(c.metadata_url))
      end

    query =
      case lock do
        "FOR SHARE" -> lock(query, "FOR SHARE")
        "FOR UPDATE" -> lock(query, "FOR UPDATE")
        nil -> query
      end

    Repo.one(query, Transaction.options())
  end

  def resolve(identifier) do
    client = find(identifier)

    cond do
      not Profile.metadata_url?(identifier) ->
        found(client)

      client && client.metadata_expires_at && Transaction.future?(client.metadata_expires_at) ->
        {:ok, client}

      true ->
        refresh(identifier, client)
    end
  end

  def digest(client),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(client.metadata, [:deterministic]))

  def internal_params(params) do
    case find(params["client_id"]) do
      %Client{} = client -> {:ok, Map.put(params, "client_id", client.public_id)}
      nil -> {:error, :invalid_grant}
    end
  end

  defp found(%Client{} = client), do: {:ok, client}
  defp found(_), do: {:error, :invalid_client}

  defp refresh(identifier, observed) do
    with {:ok, metadata, expires} <- ClientMetadata.fetch(identifier) do
      Transaction.run(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(764918320)", [], Transaction.options())

        case find(identifier, "FOR UPDATE") do
          %Client{} = current
          when is_nil(observed) or current.updated_at != observed.updated_at ->
            {:ok, current}

          %Client{} = client ->
            {:ok,
             client
             |> Ecto.Changeset.change(metadata: metadata, metadata_expires_at: expires)
             |> Repo.update!(Transaction.options())}

          nil ->
            Retention.sweep(100)

            if Repo.aggregate(Client, :count, :public_id, Transaction.options()) < 10_000 do
              {:ok,
               Repo.insert!(
                 %Client{
                   metadata_url: identifier,
                   metadata: metadata,
                   metadata_expires_at: expires
                 },
                 Transaction.options()
               )}
            else
              {:error, :quota_exceeded}
            end
        end
      end)
    end
  end
end
