defmodule Vxpipe.CallEngine.Guardrails.Deadline do
  @moduledoc false

  def evaluation_timeout_ms, do: Keyword.fetch!(settings(), :evaluation_ms)

  def evaluation(absolute \\ nil, timeout_ms \\ evaluation_timeout_ms()) do
    intersect(System.monotonic_time(:millisecond) + timeout_ms, absolute)
  end

  def response(command, request_timeout_ms \\ nil) do
    now = System.monotonic_time(:millisecond)
    maximum = now + intersect(Keyword.fetch!(settings(), :response_ms), request_timeout_ms)

    case Map.get(command, :deadline) do
      %DateTime{} = until ->
        min(maximum, now + DateTime.diff(until, DateTime.utc_now(), :millisecond))

      _ ->
        maximum
    end
  end

  def intersect(first, second) when is_integer(first) and is_integer(second),
    do: min(first, second)

  def intersect(first, _) when is_integer(first), do: first
  def intersect(_, second), do: second

  def open?(deadline), do: System.monotonic_time(:millisecond) < deadline

  defp settings, do: Application.fetch_env!(:vxpipe_call_engine, :guardrail_deadlines)
end
