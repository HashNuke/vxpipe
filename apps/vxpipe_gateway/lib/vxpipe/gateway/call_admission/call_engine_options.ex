defmodule Vxpipe.Gateway.CallAdmission.CallEngineOptions do
  @moduledoc false

  @spec build(keyword()) :: keyword()
  def build(options) when is_list(options) do
    [
      archive: Keyword.get(options, :archive, enabled: false),
      recording: Keyword.get(options, :recording, enabled: false)
    ]
    |> put_optional(:outbound_leg_connector, Keyword.get(options, :outbound_leg_connector))
  end

  defp put_optional(options, _key, nil), do: options
  defp put_optional(options, key, value), do: Keyword.put(options, key, value)
end
