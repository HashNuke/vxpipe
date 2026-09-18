defmodule Vxpipe.CallEngine.DurationLimit do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpecValidation

  @platform_default_ms 1_800_000
  @minimum_ms 1_000
  @maximum_ms 86_400_000

  @spec resolve(nil | pos_integer(), keyword()) ::
          {:ok, pos_integer()} | {:error, Vxpipe.CallEngine.Error.t()}
  def resolve(call_spec_value, options) when is_list(options) do
    with {:ok, limits} <- limits(options),
         {:ok, tenant_value} <- optional_duration(limits, :tenant),
         {:ok, application_value} <- optional_duration(limits, :application) do
      {:ok, call_spec_value || tenant_value || application_value || @platform_default_ms}
    end
  end

  defp limits(options) do
    case Keyword.get(options, :duration_limits, []) do
      value when is_list(value) ->
        if Keyword.keyword?(value) and
             Enum.all?(Keyword.keys(value), &(&1 in [:tenant, :application])) do
          {:ok, value}
        else
          invalid(["duration_limits"], "must contain only tenant and application values")
        end

      _value ->
        invalid(["duration_limits"], "must be a keyword list")
    end
  end

  defp optional_duration(limits, scope) do
    case Keyword.fetch(limits, scope) do
      :error ->
        {:ok, nil}

      {:ok, value} when is_integer(value) and value >= @minimum_ms and value <= @maximum_ms ->
        {:ok, value}

      {:ok, _value} ->
        invalid(
          ["duration_limits", Atom.to_string(scope)],
          "must be between #{@minimum_ms} and #{@maximum_ms}"
        )
    end
  end

  defp invalid(path, reason) do
    CallSpecValidation.invalid(
      :call_spec_resolution_failed,
      "The call spec could not be resolved.",
      path,
      reason
    )
  end
end
