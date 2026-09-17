defmodule Vxpipe.Calls.CallDetailsInspections do
  @moduledoc "Authorized, bounded reads of immutable call-details publications."

  alias Vxpipe.Calls.{
    CallDetailsCursor,
    CallDetailsDocument,
    CallReadAccess,
    CallDetailsRevision,
    CallDetailsRevisionPage,
    Repositories
  }

  @default_page_size 25
  @maximum_page_size 100

  @spec list(CallReadAccess.authority(), String.t(), keyword()) ::
          {:ok, CallDetailsRevisionPage.t()} | {:error, term()}
  def list(authority, call_id, options) when is_list(options) do
    with {:ok, tenant_key} <-
           CallReadAccess.tenant_key(authority, :invalid_call_details_request),
         :ok <- valid_id(call_id),
         {:ok, limit} <- page_size(options),
         {:ok, cursor} <- cursor(options),
         {:ok, repository} <-
           Repositories.fetch(options, :call_details_inspection_repository),
         {:ok, candidates} when is_list(candidates) <-
           Repositories.call(repository, :list, [
             tenant_key,
             call_id,
             limit + 1,
             cursor
           ]),
         true <- Enum.all?(candidates, &is_struct(&1, CallDetailsRevision)) do
      {:ok, page(candidates, limit)}
    else
      false -> {:error, :invalid_call_details_response}
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_call_details_response}
    end
  end

  def list(_principal, _call_id, _options), do: {:error, :invalid_call_details_request}

  @spec fetch(CallReadAccess.authority(), String.t(), String.t(), keyword()) ::
          {:ok, CallDetailsDocument.t()} | {:error, term()}
  def fetch(authority, call_id, publication_id, options)
      when is_list(options) do
    with {:ok, tenant_key} <-
           CallReadAccess.tenant_key(authority, :invalid_call_details_request),
         :ok <- valid_id(call_id),
         :ok <- valid_id(publication_id),
         {:ok, repository} <-
           Repositories.fetch(options, :call_details_inspection_repository),
         {:ok, %CallDetailsDocument{} = document} <-
           Repositories.call(repository, :fetch, [
             tenant_key,
             call_id,
             publication_id
           ]) do
      {:ok, document}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_call_details_response}
    end
  end

  def fetch(_principal, _call_id, _publication_id, _options),
    do: {:error, :invalid_call_details_request}

  defp valid_id(value)
       when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 256,
       do: :ok

  defp valid_id(_value), do: {:error, :invalid_call_details_request}

  defp page_size(options) do
    case Keyword.get(options, :limit, @default_page_size) do
      limit when is_integer(limit) and limit > 0 and limit <= @maximum_page_size -> {:ok, limit}
      _invalid -> {:error, :invalid_call_details_request}
    end
  end

  defp cursor(options) do
    case Keyword.get(options, :cursor) do
      nil -> {:ok, nil}
      encoded when is_binary(encoded) -> CallDetailsCursor.decode(encoded)
      _invalid -> {:error, :invalid_cursor}
    end
  end

  defp page(candidates, limit) do
    {revisions, overflow} = Enum.split(candidates, limit)

    %CallDetailsRevisionPage{
      revisions: revisions,
      next_cursor: next_cursor(revisions, overflow)
    }
  end

  defp next_cursor(_revisions, []), do: nil

  defp next_cursor(revisions, _overflow) do
    revision = List.last(revisions)

    CallDetailsCursor.encode(%CallDetailsCursor{
      recorded_at: revision.recorded_at,
      publication_id: revision.id
    })
  end
end
