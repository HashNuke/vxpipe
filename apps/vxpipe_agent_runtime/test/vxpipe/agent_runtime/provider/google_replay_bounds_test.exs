defmodule Vxpipe.AgentRuntime.Provider.GoogleReplayBoundsTest do
  use ExUnit.Case, async: true

  alias ReqLLM.{Context, Response, ToolCall}
  alias ReqLLM.Message.ReasoningDetails
  alias Vxpipe.AgentRuntime.Provider.ReqLLM.ResponseNormalizer

  test "valid part coverage accepts small metadata and rejects ambiguous aliases" do
    assert {:ok, _} = normalize(%{thought_signature: "small"}, "small")

    assert {:error, :invalid_provider_response} =
             normalize(%{:thought_signature => "small", "thought_signature" => "small"}, "small")

    large = String.duplicate("x", 70_000)

    assert {:error, :invalid_provider_response} =
             normalize(%{:thought_signature => large, "thought_signature" => "small"}, large)
  end

  test "part signatures and canonical tool metadata share the private byte bound" do
    small = String.duplicate("x", 10_000)
    assert {:ok, _} = normalize(%{thought_signature: small}, small)
    large = String.duplicate("x", 35_000)
    assert {:error, :invalid_provider_response} = normalize(%{thought_signature: large}, large)
  end

  defp normalize(metadata, signature) do
    {:ok, model} = ReqLLM.model("google:gemini-3.5-flash-lite")
    call = ToolCall.new("call_one", "lookup", "{}") |> ToolCall.put_metadata(metadata)

    detail = %ReasoningDetails{
      provider: :google,
      format: "google-generate-content-parts-v1",
      index: 0,
      provider_data: %{
        "part" => %{
          "functionCall" => %{"name" => "lookup", "args" => %{}},
          "thoughtSignature" => signature
        }
      }
    }

    response = %Response{
      id: "r",
      model: model.id,
      context: Context.new(),
      message: %{Context.assistant("", tool_calls: [call]) | reasoning_details: [detail]},
      finish_reason: :tool_calls,
      usage: %{}
    }

    ResponseNormalizer.normalize(response, :mode_message_v1, model)
  end
end
