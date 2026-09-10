defmodule Vxpipe.CallEngine.TestSubmittedInlineTool do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}

  @impl true
  def definition do
    %Definition{
      name: "submitted_inline_tool",
      description: "Wait for a test-controlled release.",
      parameters: %{
        "type" => "object",
        "properties" => %{"value" => %{"type" => "string"}},
        "required" => ["value"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def execute(%{"value" => value}, %Context{}) when is_binary(value) do
    observer = Application.fetch_env!(:vxpipe_call_engine, :submitted_inline_tool_observer)
    send(observer, {:submitted_inline_tool_started, self(), value})

    receive do
      :release_submitted_inline_tool -> {:ok, %{"value" => value}}
    end
  end

  def execute(_arguments, %Context{}), do: {:error, :invalid_arguments}
end
