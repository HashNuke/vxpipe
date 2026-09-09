defmodule Vxpipe.Calls.LiveInspectionSource do
  @moduledoc "Source port for one bounded engine-owned live inspection snapshot."

  alias Vxpipe.CallEngine.LiveInspection.Snapshot

  @type context :: term()

  @callback fetch(context(), String.t(), String.t()) ::
              {:ok, Snapshot.t()} | {:error, :call_not_live | term()}

  @spec read(keyword(), String.t(), String.t()) ::
          {:ok, Snapshot.t()} | {:error, :live_inspection_unavailable | term()}
  def read(options, tenant_key, call_id)
      when is_list(options) and is_binary(tenant_key) and is_binary(call_id) do
    configured = Application.get_env(:vxpipe_calls, Vxpipe.Calls, [])

    source =
      Keyword.get(
        options,
        :live_inspection_source,
        Keyword.get(configured, :live_inspection_source)
      )

    case source do
      {module, context} when is_atom(module) -> module.fetch(context, tenant_key, call_id)
      _unavailable -> {:error, :live_inspection_unavailable}
    end
  end
end
