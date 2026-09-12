defmodule Vxpipe.Calls.TestPublicationArtifactWriter do
  @moduledoc false

  @behaviour Vxpipe.Calls.PublicationArtifactWriter

  alias Vxpipe.Calls.{CallDetailsObject, CallDetailsPublication}

  @impl true
  def write(context, %CallDetailsPublication{} = publication) do
    send(context.observer, {:publication_write_started, self(), publication.id})

    case context.response do
      :success ->
        object_key = "calls/test/details/#{publication.filename}"

        CallDetailsObject.new(
          object_key,
          %{"object_key" => object_key, "etag" => "test-etag"},
          context.published_at
        )

      {:error, reason} ->
        {:error, reason}

      {:wait, release_reference} ->
        receive do
          {:release_publication_write, ^release_reference, response} -> response
        end
    end
  end
end
