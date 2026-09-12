defmodule Vxpipe.Calls.TestPublicationSource do
  @moduledoc false

  @behaviour Vxpipe.Calls.PublicationSource

  @impl true
  def read(context, tenant_key, call_id) do
    send(context.observer, {:publication_source_read, self(), tenant_key, call_id})
    context.response
  end
end
