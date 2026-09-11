defmodule Vxpipe.CallEngine.Tool.DelayedReport do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}

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
      }
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
