defmodule Vxpipe.Persistence.TestPublicationArtifactWriter do
  @moduledoc false

  @behaviour Vxpipe.Calls.PublicationArtifactWriter

  alias Vxpipe.Calls.{CallDetailsObject, CallDetailsPublication}

  @impl true
  def write(context, %CallDetailsPublication{} = publication) do
    object_key = "calls/test/#{publication.call_id}/details/#{publication.filename}"

    with {:ok, object} <-
           CallDetailsObject.new(
             object_key,
             %{"object_key" => object_key, "etag" => "test-etag-#{publication.id}"},
             Agent.get(context.clock, & &1)
           ) do
      send(context.observer, {:publication_object_written, publication.id, publication.filename})
      {:ok, object}
    end
  end
end
