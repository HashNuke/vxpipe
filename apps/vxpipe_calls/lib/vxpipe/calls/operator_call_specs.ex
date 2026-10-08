defmodule Vxpipe.Calls.OperatorCallSpecs do
  @moduledoc "Installation-authorized source reads with current revision and publication metadata."
  alias Vxpipe.Calls.{CallSpecs, InstallationOperator, ProviderAuth, Repositories}

  def fetch(%InstallationOperator{grant: :installation_operator}, tenant, id, options) do
    requested = Keyword.get(options, :revision)

    with :ok <- ProviderAuth.tenant_key(tenant),
         true <- valid_id?(id) and valid_revision?(requested),
         {:ok, repository} <- Repositories.fetch(options, :call_spec_repository),
         {:ok, next} <- Repositories.call(repository, :next_revision, [tenant, id]),
         true <- is_integer(next) and next > 1,
         {:ok, stored} <- CallSpecs.fetch(tenant, id, requested || next - 1, options),
         {:ok, published} <- published_revision(repository, tenant, id) do
      {:ok, %{call_spec: stored, latest_revision: next - 1, published_revision: published}}
    else
      false ->
        if valid_id?(id) and valid_revision?(requested),
          do: {:error, :not_found},
          else: {:error, :invalid_request}

      error ->
        error
    end
  end

  def fetch(_authority, _tenant, _id, _options),
    do: {:error, :installation_operator_required}

  defp published_revision(repository, tenant, id) do
    case Repositories.call(repository, :fetch_published_revision, [tenant, id]) do
      {:ok, stored} -> {:ok, stored.revision}
      {:error, :call_spec_not_published} -> {:ok, nil}
      error -> error
    end
  end

  defp valid_revision?(nil), do: true
  defp valid_revision?(number), do: is_integer(number) and number in 1..2_147_483_647

  defp valid_id?(id),
    do:
      is_binary(id) and byte_size(id) in 1..128 and String.valid?(id) and
        not String.contains?(id, [<<0>>, "\n", "\r"])
end
