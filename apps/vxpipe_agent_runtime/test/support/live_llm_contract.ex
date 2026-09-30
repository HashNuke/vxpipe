defmodule Vxpipe.AgentRuntime.LiveLLMContract do
  @moduledoc false
  import ExUnit.Assertions
  alias Vxpipe.AgentRuntime.{Message, ModelRequest, ModelResponse, ModelTool, ProviderSelection}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider
  alias Vxpipe.Providers.LiveModels

  def run(provider) do
    selection = LiveModels.llm(provider)

    assert {:ok, options} =
             ProviderSelection.translate(
               provider,
               selection.model,
               %{"max_tokens" => 256},
               selection.specific
             )

    options = Keyword.put(options, :api_key, System.fetch_env!(selection.env))
    assert {:ok, config} = Provider.new(options)

    tool = %ModelTool{
      name: "vxpipe_status",
      description: "Look up the fixed provider interoperability status.",
      input_schema: %{
        "type" => "object",
        "properties" => %{"value" => %{"type" => "string", "enum" => ["vxpipe"]}},
        "required" => ["value"],
        "additionalProperties" => false
      }
    }

    messages = [
      Message.system(
        "Call vxpipe_status exactly once as requested. After its result, reply briefly with the returned status."
      ),
      Message.user("Call vxpipe_status with value vxpipe.", :caller)
    ]

    first = ModelRequest.new(messages, [tool], [], %{request_id: "live_tool"})

    assert {:ok, %ModelResponse{tool_calls: [call]} = response} =
             Provider.stream(config, first, fn _ -> :ok end)

    assert call.name == "vxpipe_status"
    assert call.arguments == %{"value" => "vxpipe"}

    continuation =
      ModelRequest.new(
        messages ++
          [Message.assistant(response.text, [call]), Message.tool(call, %{"status" => "READY"})],
        [],
        [],
        %{request_id: "live_continuation"}
      )

    assert {:ok, %ModelResponse{text: text, tool_calls: []} = completed} =
             Provider.stream(config, continuation, fn _ -> :ok end)

    assert String.trim(text) != ""
    assert map_size(response.usage) > 0 or map_size(completed.usage) > 0
    :ok
  end
end
