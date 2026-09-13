defmodule Vxpipe.CallEngine.CallDefinition.WaitSoundsCompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation, DefinitionCompiler, Error}

  test "omitted slots resolve destination-specific defaults while explicit nil silences only its slot" do
    assert CallDefinition.schema_version() == "20260914.01"

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
    assert {:ok, authored} = CallDefinition.new(input, resource_id: "support", revision: 1)

    assert {:ok, json} =
             CallDefinition.from_json(JSON.encode!(input), resource_id: "support", revision: 1)

    assert json == authored
    plan = compile(fields)
    assert plan.wait_sounds.transfer_to_agent == fields.wait_sounds.transfer_to_agent
    assert plan.wait_sounds.transfer_to_human == fields.wait_sounds.transfer_to_human
    assert plan.wait_sounds.call_setup == nil
    assert plan.wait_sounds.transfer_joining == nil
    refute inspect(plan) =~ "media.example.com"
  end

  test "current definitions remain supported and retain their schema while rejecting new fields" do
    plan = compile(%{schema_version: "20260913.01"})
    assert plan.schema_version == "20260913.01"
    assert plan.wait_sounds.transfer_joining == :cafe_bossa

    assert {:error, %Error{details: %{"path" => ["wait_sounds"]}}} =
             input()
             |> Map.merge(%{schema_version: "20260913.01", wait_sounds: nil})
             |> CallDefinition.new(resource_id: "support", revision: 1)
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
               |> CallDefinition.new(resource_id: "support", revision: 1)
    end

    for value <- [true, "https://media.example.com/a.wav", []] do
      assert {:error, %Error{details: %{"path" => ["wait_sounds"]}}} =
               input()
               |> Map.put(:wait_sounds, value)
               |> CallDefinition.new(resource_id: "support", revision: 1)
    end

    assert {:error, %Error{details: %{"path" => ["wait_sounds", "unknown"]}}} =
             input()
             |> Map.put(:wait_sounds, %{"unknown" => nil})
             |> CallDefinition.new(resource_id: "support", revision: 1)
  end

  test "prepares previously pinned plans without rewriting their original schema or identities" do
    plan = compile(%{schema_version: "20260913.01"})
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
    assert {:ok, definition} =
             input()
             |> Map.merge(fields)
             |> CallDefinition.new(resource_id: "support", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_definition: %{id: "support", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, plan} =
             DefinitionCompiler.compile(definition, invocation, %{
               capability_profiles: %{},
               host_tools: %{}
             })

    plan
  end

  defp input do
    %{
      schema_version: CallDefinition.schema_version(),
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
