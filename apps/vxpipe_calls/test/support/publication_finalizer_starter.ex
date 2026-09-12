defmodule Vxpipe.Calls.TestPublicationFinalizerStarter do
  @moduledoc false

  @behaviour Vxpipe.Calls.PublicationFinalizerStarter

  def start(tenant_key, call_id, options) do
    observer = Keyword.fetch!(options, :publication_trigger_observer)
    send(observer, {:publication_finalization_requested, tenant_key, call_id})
    Keyword.get(options, :publication_trigger_response, {:ok, self(), :started})
  end
end
