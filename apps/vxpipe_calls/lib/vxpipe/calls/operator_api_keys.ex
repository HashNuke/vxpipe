defmodule Vxpipe.Calls.OperatorApiKeys do
  @moduledoc """
  Installation API-key authentication and trusted local lifecycle operations.

  Bootstrap, replacement and revocation require trusted host access. They must not
  be exposed as unauthenticated HTTP operations. Browser login is independent.
  """
  alias Vxpipe.Calls.{InstallationOperator, IssuedOperatorApiKey, PublicId, Repositories}

  def bootstrap(options), do: issue(:bootstrap, options)
  def replace(options), do: issue(:replace, options)

  def authenticate(secret, options) do
    with true <- valid_secret?(secret),
         {:ok, repository} <- Repositories.fetch(options, :operator_api_key_repository),
         {:ok, %{id: id, revoked_at: nil}} <-
           Repositories.call(repository, :fetch, [:crypto.hash(:sha256, secret)]) do
      {:ok, %InstallationOperator{grant: :installation_operator, api_key_id: id}}
    else
      false -> {:error, :invalid_api_key}
      {:ok, _revoked} -> {:error, :invalid_api_key}
      {:error, :not_found} -> {:error, :invalid_api_key}
      {:error, _reason} = error -> error
    end
  end

  def revoke(id, options) do
    with :ok <- valid_id(id),
         {:ok, repository} <- Repositories.fetch(options, :operator_api_key_repository),
         {:ok, record} <- Repositories.call(repository, :revoke, [id, now(options)]) do
      {:ok, Map.take(record, [:id, :revoked_at])}
    end
  end

  defp issue(mode, options) do
    with {:ok, repository} <- Repositories.fetch(options, :operator_api_key_repository) do
      issued = %IssuedOperatorApiKey{
        id: Keyword.get(options, :uuid_generator, &PublicId.uuid/0).(),
        secret: "vxop_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false),
        inserted_at: now(options)
      }

      record = %{
        id: issued.id,
        digest: :crypto.hash(:sha256, issued.secret),
        inserted_at: issued.inserted_at,
        revoked_at: nil
      }

      with {:ok, _stored} <- Repositories.call(repository, :issue, [record, mode]),
           do: {:ok, issued}
    end
  end

  defp valid_secret?(secret) when is_binary(secret),
    do: Regex.match?(~r/\Avxop_[A-Za-z0-9_-]{43}\z/, secret)

  defp valid_secret?(_secret), do: false

  defp valid_id(id) when is_binary(id) do
    if Regex.match?(
         ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/,
         id
       ), do: :ok, else: {:error, :invalid_api_key_id}
  end

  defp valid_id(_id), do: {:error, :invalid_api_key_id}
  defp now(options), do: Keyword.get_lazy(options, :now, &DateTime.utc_now/0)
end
