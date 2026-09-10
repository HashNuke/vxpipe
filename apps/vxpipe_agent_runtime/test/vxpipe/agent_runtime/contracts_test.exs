defmodule Vxpipe.AgentRuntime.ContractsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Event, Request, Result, ToolDescriptor}

  test "builds a tool descriptor while keeping its private binding out of inspection" do
    binding = %{credential: "not-model-visible", operation: "lookup_order"}

    assert {:ok, descriptor} =
             ToolDescriptor.new(
               name: "lookup_order",
               description: "Look up an order",
               input_schema: %{
                 "type" => "object",
                 "properties" => %{"order_id" => %{"type" => "string"}},
                 "required" => ["order_id"]
               },
               binding: binding
             )

    assert descriptor.name == "lookup_order"
    assert descriptor.binding == binding
    refute inspect(descriptor) =~ "not-model-visible"
  end

  test "rejects malformed tool descriptors at construction" do
    assert {:error, :invalid_name} =
             ToolDescriptor.new(
               name: "",
               description: "Invalid",
               input_schema: %{"type" => "object"},
               binding: :private
             )

    assert {:error, :invalid_input_schema} =
             ToolDescriptor.new(
               name: "lookup_order",
               description: "Invalid",
               input_schema: %{"type" => "not-a-json-schema-type"},
               binding: :private
             )
  end

  test "constructs bounded request, result, and event values" do
    assert {:ok, request} = Request.new("hello", %{request_id: "req_1"})
    assert request.input == "hello"
    assert request.correlation == %{request_id: "req_1"}

    assert %Result{status: :completed, output: "hi", correlation: %{request_id: "req_1"}} =
             Result.completed("hi", request.correlation)

    assert %Event{kind: :request_started, correlation: %{request_id: "req_1"}, data: %{}} =
             Event.new(:request_started, request.correlation)

    assert {:error, :input_too_large} =
             Request.new(String.duplicate("x", 17), %{}, max_input_bytes: 16)
  end
end
