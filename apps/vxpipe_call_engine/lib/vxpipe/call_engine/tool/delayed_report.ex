defmodule Vxpipe.CallEngine.Tool.DelayedReport do
  @moduledoc false

  use Jido.Action,
    name: "prepare_background_report",
    description: "Prepare a deterministic report after a bounded delay.",
    schema: [
      topic: [type: :string, required: true],
      delay_ms: [type: :non_neg_integer, default: 2_000]
    ]

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition, Dispatcher}

  @maximum_delay_ms 10_000
  @maximum_topic_bytes 256

  @impl Vxpipe.CallEngine.Tool
  def definition do
    %Definition{
      name: "prepare_background_report",
      description: "Prepare a deterministic report after a bounded delay.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "topic" => %{"type" => "string", "minLength" => 1, "maxLength" => 256},
          "delay_ms" => %{
            "type" => "integer",
            "minimum" => 0,
            "maximum" => @maximum_delay_ms,
            "default" => 2_000
          }
        },
        "required" => ["topic"],
        "additionalProperties" => false
      },
      execution: :background
    }
  end

  @impl Vxpipe.CallEngine.Tool
  def execute(arguments, %Context{}) when is_map(arguments) do
    topic = Map.get(arguments, "topic", Map.get(arguments, :topic))
    delay_ms = Map.get(arguments, "delay_ms", Map.get(arguments, :delay_ms, 2_000))

    if valid_topic?(topic) and is_integer(delay_ms) and delay_ms >= 0 and
         delay_ms <= @maximum_delay_ms do
      wait(delay_ms)

      {:ok,
       %{
         "status" => "ready",
         "summary" => "The background report for #{String.trim(topic)} is ready.",
         "topic" => String.trim(topic)
       }}
    else
      {:error, :invalid_arguments}
    end
  end

  @impl Jido.Action
  def run(arguments, context) when is_map(arguments) and is_map(context) do
    with dispatcher when not is_nil(dispatcher) <- Map.get(context, :vxpipe_tool_dispatcher),
         %Context{} = tool_context <- Map.get(context, :vxpipe_tool_context) do
      Dispatcher.submit(dispatcher, name(), arguments, tool_context)
    else
      _invalid -> {:error, :tool_failed}
    end
  end

  defp valid_topic?(topic) when is_binary(topic) do
    String.valid?(topic) and String.trim(topic) != "" and byte_size(topic) <= @maximum_topic_bytes
  end

  defp valid_topic?(_topic), do: false

  defp wait(0), do: :ok

  defp wait(delay_ms) do
    receive do
    after
      delay_ms -> :ok
    end
  end
end
