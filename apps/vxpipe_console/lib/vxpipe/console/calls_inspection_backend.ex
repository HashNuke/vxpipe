defmodule Vxpipe.Console.CallsInspectionBackend do
  @moduledoc false

  @behaviour Vxpipe.Console.CallInspectionBackend

  alias Vxpipe.Calls

  @impl true
  def list_calls(options, principal, request_options) do
    Calls.list_calls(principal, Keyword.merge(request_options, options))
  end

  @impl true
  def inspect_call(options, principal, call_id, request_options) do
    Calls.inspect_call(principal, call_id, Keyword.merge(request_options, options))
  end

  @impl true
  def inspect_live_call(options, principal, call_id, request_options) do
    Calls.inspect_live_call(principal, call_id, Keyword.merge(request_options, options))
  end

  @impl true
  def usage_report(options, principal, call_id, request_options) do
    Calls.fetch_usage_report(principal, call_id, Keyword.merge(request_options, options))
  end

  @impl true
  def fetch_definition(options, tenant_key, definition_id, revision, request_options) do
    Calls.fetch_definition(
      tenant_key,
      definition_id,
      revision,
      Keyword.merge(request_options, options)
    )
  end
end
