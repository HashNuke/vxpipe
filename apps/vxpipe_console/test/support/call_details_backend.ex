defmodule Vxpipe.Console.TestCallDetailsBackend do
  @moduledoc false

  @behaviour Vxpipe.Console.CallDetailsBackend

  @impl true
  def list({observer, responses}, principal, call_id, options) do
    send(observer, {:list_call_details, principal, call_id, options})
    Map.fetch!(responses, :list)
  end

  @impl true
  def fetch({observer, responses}, principal, call_id, publication_id, options) do
    send(observer, {:fetch_call_details, principal, call_id, publication_id, options})
    Map.fetch!(responses, :fetch)
  end
end
