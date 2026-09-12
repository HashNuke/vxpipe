defmodule Vxpipe.Artifacts.CallDetailsWriter do
  @moduledoc "Writes a reserved call-details revision below its protected call-owned prefix."

  @behaviour Vxpipe.Calls.PublicationArtifactWriter

  alias Vxpipe.Artifacts.{Document, DocumentObjectStore}
  alias Vxpipe.Calls.{CallDetailsObject, CallDetailsPublication}

  @impl true
  def write(options, %CallDetailsPublication{status: :pending} = publication)
      when is_list(options) do
    with {:ok, store} <- document_store(options),
         {:ok, store_options} <- keyword(options, :document_store_options, []),
         {:ok, published_at} <- timestamp(options),
         object_key = object_key(publication),
         {:ok, document} <- Document.new(object_key, publication.contents, publication.checksum),
         {:ok, reference} <- store.put(document, store_options) do
      CallDetailsObject.new(object_key, reference, published_at)
    end
  end

  def write(_options, _publication), do: {:error, :invalid_call_details_write}

  defp document_store(options) do
    case Keyword.get(options, :document_store, Vxpipe.Artifacts.S3DocumentStore) do
      module when is_atom(module) ->
        if DocumentObjectStore.valid?(module),
          do: {:ok, module},
          else: {:error, :invalid_document_store}

      _invalid ->
        {:error, :invalid_document_store}
    end
  end

  defp timestamp(options) do
    case Keyword.get_lazy(options, :now, fn -> DateTime.utc_now(:millisecond) end) do
      %DateTime{} = value -> {:ok, value}
      _invalid -> {:error, :invalid_publication_timestamp}
    end
  end

  defp keyword(options, key, default) do
    case Keyword.get(options, key, default) do
      value when is_list(value) -> {:ok, value}
      _invalid -> {:error, :invalid_call_details_write}
    end
  end

  defp object_key(publication) do
    tenant = Base.url_encode64(publication.tenant_key, padding: false)
    call = Base.url_encode64(publication.call_id, padding: false)
    "calls/#{tenant}/#{call}/details/#{publication.filename}"
  end
end
