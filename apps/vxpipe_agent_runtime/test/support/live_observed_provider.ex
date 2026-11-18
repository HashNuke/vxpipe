defmodule Vxpipe.AgentRuntime.LiveObservedProvider do
  @moduledoc false
  @behaviour Vxpipe.AgentRuntime.ModelProvider
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  @impl true
  defdelegate readiness(config), to: Provider
  @impl true
  defdelegate streaming?(config), to: Provider
  @impl true
  defdelegate context_window_tokens(config), to: Provider
  @impl true
  defdelegate maximum_output_tokens(config), to: Provider
  @impl true
  defdelegate supports_protocol?(config, protocol, tools), to: Provider

  @impl true
  def generate(config, request), do: observe(Provider.generate(config, request), request)
  @impl true
  def stream(config, request, emit), do: observe(Provider.stream(config, request, emit), request)

  def observe_transport(_event, _measurements, metadata, _config) do
    IO.puts(
      "UNIVERSAL_REPLY_TRANSPORT " <>
        JSON.encode!(%{
          finish_reason: metadata[:finish_reason],
          http_status: metadata[:http_status],
          summary: Map.take(metadata[:response_summary] || %{}, [:tool_call_count, :text_bytes])
        })
    )
  end

  defp observe({:ok, response} = result, request) do
    # Only used by the synthetic live fixture. Never log config, headers or replay.
    IO.puts(
      "UNIVERSAL_REPLY_RESPONSE " <>
        JSON.encode!(%{
          step: request.correlation[:request_id],
          tools: Enum.map(response.tool_calls, & &1.name),
          text: response.text
        })
    )

    result
  end

  defp observe(error, _request), do: error
end
