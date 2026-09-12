defmodule Vxpipe.Calls.PublicationSources do
  @moduledoc false

  alias Vxpipe.Calls.PublicationSource

  @spec fetch(keyword()) ::
          {:ok, {module(), term()}} | {:error, :publication_source_unavailable}
  def fetch(options) when is_list(options) do
    configured = Application.get_env(:vxpipe_calls, Vxpipe.Calls, [])
    publication = Keyword.get(configured, :call_details_publication, [])

    source =
      Keyword.get(
        options,
        :publication_source,
        Keyword.get(
          publication,
          :publication_source,
          Keyword.get(configured, :publication_source)
        )
      )

    case source do
      {module, _context} = adapter when is_atom(module) ->
        if PublicationSource.valid?(module),
          do: {:ok, adapter},
          else: {:error, :publication_source_unavailable}

      _unavailable ->
        {:error, :publication_source_unavailable}
    end
  end

  def fetch(_options), do: {:error, :publication_source_unavailable}
end
