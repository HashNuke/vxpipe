defmodule Vxpipe.CallEngine.CallVariablesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallDefinition
  alias Vxpipe.CallEngine.CallInvocation
  alias Vxpipe.CallEngine.CallVariables
  alias Vxpipe.CallEngine.Command.{ReadCallVariables, UpdateCallVariables}
  alias Vxpipe.CallEngine.DefinitionCompiler
  alias Vxpipe.CallEngine.Error

  @schema_version "20260906.02"

  test "reads only requested authorized sections and fails a mixed forbidden read without values" do
    %{server: server, identity: identity} = start_variables()

    assert {:ok, command} =
             ReadCallVariables.new(
               identity ++
                 [sections: ["customer", "intake"], deadline: deadline()]
             )

    assert {:ok,
            %{
              "global_revision" => 0,
              "sections" => %{
                "customer" => %{
                  "revision" => 0,
                  "value" => %{
                    "id" => "customer-1",
                    "profile" => %{
                      "city" => "Exampleville",
                      "postal_code" => "12345"
                    }
                  }
                },
                "intake" => %{"revision" => 0, "value" => nil}
              }
            }} = CallVariables.read(server, command)

    assert {:ok, forbidden} =
             ReadCallVariables.new(
               identity ++
                 [sections: ["customer", "private"], deadline: deadline()]
             )

    assert {:error,
            %Error{
              code: :call_variables_forbidden,
              details: %{"section" => "private"}
            } = error} = CallVariables.read(server, forbidden)

    refute inspect(error) =~ "customer-1"
    refute inspect(error) =~ "Exampleville"
  end

  test "authorizes the pinned tenant, room, incarnation, and participant identity" do
    %{server: server, identity: identity} = start_variables()

    for field <- [:tenant_id, :room_id, :incarnation_id, :participant_id] do
      assert {:ok, command} =
               ReadCallVariables.new(
                 identity
                 |> Keyword.put(field, "wrong")
                 |> Keyword.merge(sections: ["customer"], deadline: deadline())
               )

      assert {:error, %Error{code: :call_variables_forbidden, details: %{}}} =
               CallVariables.read(server, command)
    end
  end

  test "recursively merges objects, replaces arrays, clears nullable values, and advances revisions" do
    %{server: server, identity: identity} = start_variables()

    assert {:ok, first} =
             update_command(identity,
               section: "intake",
               expected_revision: 0,
               operation:
                 {:merge,
                  %{
                    "address" => %{
                      "city" => "First City",
                      "postal_code" => "12345"
                    },
                    "labels" => ["first"],
                    "note" => "temporary"
                  }}
             )

    assert {:ok,
            %{
              "section" => "intake",
              "revision" => 1,
              "global_revision" => 1,
              "value" => first_value
            }} = CallVariables.update(server, first)

    assert first_value["address"]["postal_code"] == "12345"

    assert {:ok, second} =
             update_command(identity,
               section: "intake",
               expected_revision: 1,
               operation:
                 {:merge,
                  %{
                    "address" => %{"city" => "Second City"},
                    "labels" => ["replacement"],
                    "note" => nil
                  }}
             )

    assert {:ok,
            %{
              "revision" => 2,
              "global_revision" => 2,
              "value" => %{
                "address" => %{
                  "city" => "Second City",
                  "postal_code" => "12345"
                },
                "labels" => ["replacement"],
                "note" => nil
              }
            }} = CallVariables.update(server, second)
  end

  test "updates a literal variable and rejects unknown, invalid, and stale updates atomically" do
    %{server: server, identity: identity} = start_variables()

    assert {:ok, direct} =
             update_command(identity,
               section: "intake",
               expected_revision: 0,
               operation: {:put, "summary", "Collected details"}
             )

    assert {:ok, %{"revision" => 1, "value" => %{"summary" => "Collected details"}}} =
             CallVariables.update(server, direct)

    invalid_operations = [
      {{:put, "summary.extra", "not a path"}, :invalid_call_variables_update},
      {{:put, "priority", "high"}, :invalid_call_variables_update},
      {{:merge, %{"priority" => 1, "unknown" => true}}, :invalid_call_variables_update}
    ]

    for {operation, code} <- invalid_operations do
      assert {:ok, command} =
               update_command(identity,
                 section: "intake",
                 expected_revision: 1,
                 operation: operation
               )

      assert {:error, %Error{code: ^code}} = CallVariables.update(server, command)
    end

    assert {:ok, stale} =
             update_command(identity,
               section: "intake",
               expected_revision: 0,
               operation: {:put, "priority", 1}
             )

    assert {:error,
            %Error{
              code: :call_variables_revision_conflict,
              details: %{"section" => "intake", "current_revision" => 1}
            }} = CallVariables.update(server, stale)

    assert {:ok, read} =
             ReadCallVariables.new(identity ++ [sections: ["intake"], deadline: deadline()])

    assert {:ok,
            %{
              "global_revision" => 1,
              "sections" => %{
                "intake" => %{
                  "revision" => 1,
                  "value" => %{"summary" => "Collected details"}
                }
              }
            }} = CallVariables.read(server, read)
  end

  test "rejects expired and oversized work without mutation" do
    %{server: server, identity: identity} = start_variables()

    assert {:ok, expired_read} =
             ReadCallVariables.new(
               identity ++
                 [sections: ["intake"], deadline: DateTime.add(DateTime.utc_now(), -1)]
             )

    assert {:error, %Error{code: :deadline_exceeded}} =
             CallVariables.read(server, expired_read)

    assert {:ok, oversized} =
             update_command(identity,
               section: "intake",
               expected_revision: 0,
               operation: {:put, "summary", String.duplicate("x", 20_000)}
             )

    assert {:error, %Error{code: :invalid_call_variables_update}} =
             CallVariables.update(server, oversized)

    assert {:ok, read} =
             ReadCallVariables.new(identity ++ [sections: ["intake"], deadline: deadline()])

    assert {:ok,
            %{
              "global_revision" => 0,
              "sections" => %{"intake" => %{"revision" => 0, "value" => nil}}
            }} = CallVariables.read(server, read)
  end

  defp start_variables do
    plan = resolved_plan()
    incarnation_id = "rinc-test"

    server =
      start_supervised!(
        {CallVariables, plan: plan, incarnation_id: incarnation_id, register: false}
      )

    participant = plan.participants["reception"]

    %{
      server: server,
      identity: [
        tenant_id: plan.tenant_id,
        room_id: plan.room_id,
        incarnation_id: incarnation_id,
        participant_id: participant.participant_id
      ]
    }
  end

  defp update_command(identity, options) do
    UpdateCallVariables.new(
      identity ++
        options ++
        [
          activation_id: "act-test",
          source_participant_id: "part-caller",
          correlation_id: "corr-test",
          tool_call_id: "tool-call-test",
          deadline: deadline()
        ]
    )
  end

  defp resolved_plan do
    assert {:ok, definition} =
             CallDefinition.new(definition_input(), resource_id: "support", revision: 1)

    invocation_input = %{
      call_definition: %{id: "support", revision: 1},
      initial_variables: %{
        "customer" => %{
          "id" => "customer-1",
          "profile" => %{
            "city" => "Exampleville",
            "postal_code" => "12345"
          }
        }
      },
      transport: %{type: "web"}
    }

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input,
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries())
    plan
  end

  defp definition_input do
    %{
      schema_version: @schema_version,
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{capabilities: %{model_inference: "default-model"}},
      call_variables: %{
        sections: %{
          "customer" => %{
            schema: %{
              "type" => "object",
              "properties" => %{
                "id" => %{"type" => "string"},
                "profile" => %{
                  "type" => "object",
                  "properties" => %{
                    "city" => %{"type" => "string"},
                    "postal_code" => %{"type" => "string"}
                  },
                  "additionalProperties" => false
                }
              },
              "additionalProperties" => false
            }
          },
          "intake" => %{
            schema: %{
              "type" => "object",
              "properties" => %{
                "summary" => %{"type" => "string"},
                "priority" => %{"type" => "integer"},
                "address" => %{
                  "type" => "object",
                  "properties" => %{
                    "city" => %{"type" => "string"},
                    "postal_code" => %{"type" => "string"}
                  },
                  "additionalProperties" => false
                },
                "labels" => %{"type" => "array", "items" => %{"type" => "string"}},
                "note" => %{"type" => ["string", "null"]}
              },
              "additionalProperties" => false
            }
          },
          "private" => %{
            schema: %{
              "type" => "object",
              "properties" => %{"secret" => %{"type" => "string"}},
              "additionalProperties" => false
            }
          }
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "reception" => %{
          type: "agent",
          prompt: "Answer clearly.",
          variable_permissions: %{
            "customer" => ["read"],
            "intake" => ["read", "write"]
          }
        }
      }
    }
  end

  defp registries do
    %{
      capability_profiles: %{
        "default-model" => %{
          kind: :model_inference,
          provider: :test_model,
          options: %{model: "default"}
        }
      },
      host_tools: %{}
    }
  end

  defp deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)
end
