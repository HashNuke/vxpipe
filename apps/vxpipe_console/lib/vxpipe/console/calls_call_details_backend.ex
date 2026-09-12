defmodule Vxpipe.Console.CallsCallDetailsBackend do
  @moduledoc false

  @behaviour Vxpipe.Console.CallDetailsBackend

  alias Vxpipe.Calls

  @impl true
  def list(options, principal, call_id, request_options) do
    Calls.list_call_details(principal, call_id, Keyword.merge(request_options, options))
  end

  @impl true
  def fetch(options, principal, call_id, publication_id, request_options) do
    Calls.fetch_call_details(
      principal,
      call_id,
      publication_id,
      Keyword.merge(request_options, options)
    )
  end
end
