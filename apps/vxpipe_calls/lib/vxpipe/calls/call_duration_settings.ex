defmodule Vxpipe.Calls.CallDurationSettings do
  @moduledoc false

  @spec compiler_options(String.t(), keyword()) ::
          {:ok, keyword()} | {:error, :call_duration_settings_unavailable}
  def compiler_options(tenant_key, options) when is_binary(tenant_key) and is_list(options) do
    configured = Application.get_env(:vxpipe_calls, Vxpipe.Calls, [])
    settings = Keyword.get(options, :call_duration, Keyword.get(configured, :call_duration, []))

    with {:ok, settings} <- settings(settings),
         {:ok, tenant_settings} <- tenant_settings(settings, tenant_key) do
      duration_limits =
        []
        |> put_present(:application, Keyword.get(settings, :max_duration_ms))
        |> put_present(:tenant, Keyword.get(tenant_settings, :max_duration_ms))

      {:ok, [duration_limits: duration_limits]}
    end
  end

  defp settings(value) when is_list(value) do
    if Keyword.keyword?(value) and
         Enum.all?(Keyword.keys(value), &(&1 in [:max_duration_ms, :tenants])) do
      {:ok, value}
    else
      unavailable()
    end
  end

  defp settings(_value), do: unavailable()

  defp tenant_settings(settings, tenant_key) do
    case Keyword.get(settings, :tenants, %{}) do
      tenants when is_map(tenants) ->
        case Map.get(tenants, tenant_key, []) do
          value when is_list(value) ->
            if Keyword.keyword?(value) and
                 Enum.all?(Keyword.keys(value), &(&1 == :max_duration_ms)) do
              {:ok, value}
            else
              unavailable()
            end

          _value ->
            unavailable()
        end

      _value ->
        unavailable()
    end
  end

  defp put_present(options, _key, nil), do: options
  defp put_present(options, key, value), do: Keyword.put(options, key, value)

  defp unavailable, do: {:error, :call_duration_settings_unavailable}
end
