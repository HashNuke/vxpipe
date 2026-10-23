defmodule Vxpipe.Gateway.CallAdmission.CallEngineOptions do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.OutgoingLegConnector

  def build(options, call) do
    runtime = build(options)

    if Keyword.get(options, :managed_cleanup, false) == true do
      scope_connector(runtime, options, call)
    else
      {:ok, runtime}
    end
  end

  @spec build(keyword()) :: keyword()
  def build(options) when is_list(options) do
    [
      archive: Keyword.get(options, :archive, enabled: false),
      recording: Keyword.get(options, :recording, enabled: false)
    ]
    |> put_optional(:outbound_leg_connector, Keyword.get(options, :outbound_leg_connector))
    |> put_optional(:credential_source, Keyword.get(options, :credential_source))
  end

  defp put_optional(options, _key, nil), do: options
  defp put_optional(options, key, value), do: Keyword.put(options, key, value)

  defp scope_connector(runtime, options, call) do
    case Keyword.fetch(runtime, :outbound_leg_connector) do
      {:ok, {OutgoingLegConnector, connector_options}} ->
        cleanup_options =
          options |> Keyword.get(:cleanup_options, []) |> Keyword.put(:calls_options, options)

        scoped =
          Keyword.merge(connector_options,
            cleanup_scope: %{tenant_key: call.tenant_key, call_id: call.id, room_id: call.room_id},
            cleanup_options: cleanup_options
          )

        {:ok, Keyword.put(runtime, :outbound_leg_connector, {OutgoingLegConnector, scoped})}

      :error ->
        {:ok, runtime}

      _unsupported ->
        {:error, :cleanup_connector_unavailable}
    end
  end
end
