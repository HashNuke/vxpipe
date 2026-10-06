defmodule Vxpipe.CallEngine.CallSpec.WaitSoundsCompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallSpec, CallInvocation, CallSpecCompiler, Error}

  test "omitted slots resolve destination-specific defaults while explicit nil silences only its slot" do
    assert CallSpec.schema_version() == "20261004.01"

    for fields <- [%{}, %{wait_sounds: %{}}] do
      plan = compile(fields)
      assert plan.wait_sounds.call_setup == :phone_ring
      assert plan.wait_sounds.transfer_to_agent == :cafe_bossa
      assert plan.wait_sounds.transfer_to_human == :phone_ring
      assert plan.wait_sounds.transfer_joining == :cafe_bossa
    end

    plan = compile(%{wait_sounds: %{transfer_to_human: nil}})
    assert plan.wait_sounds.transfer_to_human == nil
    assert plan.wait_sounds.transfer_joining == :cafe_bossa
    assert plan.wait_sounds.call_setup == :phone_ring
  end

  test "whole-object nil silences all slots" do
    plan = compile(%{wait_sounds: nil})
    assert Enum.all?(Map.from_struct(plan.wait_sounds), fn {_slot, value} -> is_nil(value) end)
  end

  test "JSON and Elixir retain exact URL selections and nil without exposing URLs in inspection" do
    fields = %{
      wait_sounds: %{
        call_setup: nil,
        transfer_to_agent: "https://media.example.com/agent.wav?version=2",
        transfer_to_human: "http://media.example.com/human.wav",
        transfer_joining: nil
      }
    }

    input = Map.merge(input(), fields)
    assert {:ok, authored} = CallSpec.new(input, resource_id: "support", revision: 1)

    assert {:ok, json} =
             CallSpec.from_json(JSON.encode!(input), resource_id: "support", revision: 1)

    assert json == authored
    plan = compile(fields)
    assert plan.wait_sounds.transfer_to_agent == fields.wait_sounds.transfer_to_agent
    assert plan.wait_sounds.transfer_to_human == fields.wait_sounds.transfer_to_human
    assert plan.wait_sounds.call_setup == nil
    assert plan.wait_sounds.transfer_joining == nil
    refute inspect(plan) =~ "media.example.com"
  end

  test "retired schema call specs require explicit conversion" do
    assert {:error, %Error{details: %{"path" => ["schema_version"]}}} =
             input()
             |> Map.merge(%{schema_version: "20260913.01", wait_sounds: nil})
             |> CallSpec.new(resource_id: "support", revision: 1)
  end

  test "rejects unknown slots and configured non-URLs at the authored path" do
    invalid = [
      true,
      42,
      "cafe-bossa",
      "",
      %{},
      [],
      "/wait.wav",
      "file:///wait.wav",
      "data:audio/wav;base64,AAAA",
      "https://",
      "ftp://media.example.com/a.wav",
      "https://user:pass@media.example.com/a.wav",
      "https://media.example.com/a.wav#part"
    ]

    for value <- invalid do
      assert {:error, %Error{details: %{"path" => ["wait_sounds", "transfer_joining"]}}} =
               input()
               |> Map.put(:wait_sounds, %{transfer_joining: value})
               |> CallSpec.new(resource_id: "support", revision: 1)
    end

    for value <- [true, "https://media.example.com/a.wav", []] do
      assert {:error, %Error{details: %{"path" => ["wait_sounds"]}}} =
               input()
               |> Map.put(:wait_sounds, value)
               |> CallSpec.new(resource_id: "support", revision: 1)
    end

    assert {:error, %Error{details: %{"path" => ["wait_sounds", "unknown"]}}} =
             input()
             |> Map.put(:wait_sounds, %{"unknown" => nil})
             |> CallSpec.new(resource_id: "support", revision: 1)
  end

  test "prepares decoded current plans without rewriting their schema or identities" do
    plan = compile(%{})
    legacy = Map.drop(plan, [:wait_sounds, :wait_sound_assets])
    encoded = :erlang.term_to_binary(legacy, [:deterministic])
    decoded = :erlang.binary_to_term(encoded, [:safe])

    assert {:ok, prepared} = Vxpipe.CallEngine.prepare_call_audio(decoded)
    assert prepared.schema_version == plan.schema_version
    assert prepared.call_id == plan.call_id
    assert prepared.participants == plan.participants
    assert prepared.wait_sounds.transfer_joining == :cafe_bossa
    assert map_size(prepared.wait_sound_assets.assets) == 3
    assert :erlang.term_to_binary(decoded, [:deterministic]) == encoded
    assert {:ok, ^prepared} = Vxpipe.CallEngine.prepare_call_audio(prepared)
  end

  defp compile(fields) do
    assert {:ok, call_spec} =
             input()
             |> Map.merge(fields)
             |> CallSpec.new(resource_id: "support", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_spec: %{id: "support", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation, %{
               host_tools: %{}
             })

    plan
  end

  defp input do
    %{
      schema_version: "20260915.01",
      entry_caller: "caller",
      entry_receiver: "support",
      participants:
        Map.new(["caller", "support"], fn key ->
          {key,
           %{
             type: "human",
             connection: %{service: "web", mode: "receive", admission: "start_call"}
           }}
        end)
    }
  end
end
