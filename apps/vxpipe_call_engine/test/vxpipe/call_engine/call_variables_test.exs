defmodule Vxpipe.CallEngine.CallVariablesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallDefinition
  alias Vxpipe.CallEngine.CallInvocation
  alias Vxpipe.CallEngine.CallVariables
  alias Vxpipe.CallEngine.Archive.Handoff
  alias Vxpipe.CallEngine.Archive.Supervisor, as: ArchiveSupervisor
  alias Vxpipe.CallEngine.CallVariables.{BaselineSnapshot, UpdateSnapshot}
  alias Vxpipe.CallEngine.Command.{ReadCallVariables, UpdateCallVariables}
  alias Vxpipe.CallEngine.DefinitionCompiler
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.TestArchiveWriter

  @schema_version "20260913.01"

  test "readiness exposes initialized bindings without values or invalidation by ordinary updates" do
    %{server: server, identity: identity} = start_variables()
    assert {:ok, resource, :ready} = CallVariables.readiness(server)
    assert resource.kind == :call_variables
    assert resource.scope == :room
    refute inspect(resource) =~ "customer-1"
    refute inspect(resource) =~ "Exampleville"

    assert {:ok, command} =
             update_command(identity,
               section: "intake",
               expected_revision: 0,
               operation: {:merge, %{"note" => "new value"}}
             )

    assert {:ok, _result} = CallVariables.update(server, command)
    assert {:ok, ^resource, :ready} = CallVariables.readiness(server)
  end

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

  test "hands an exact baseline and accepted update through the bounded private archive" do
    handoff = open_archive()
    %{server: server, identity: identity, plan: plan} = start_variables(archive_handoff: handoff)

    assert_receive {:test_archive_write, baseline_writer,
                    %BaselineSnapshot{
                      id: "vsnap_" <> _,
                      tenant_id: "tenant-demo",
                      call_id: call_id,
                      room_id: room_id,
                      incarnation_id: "rinc-test",
                      global_revision: 0,
                      sections: baseline_sections,
                      source_policy: %{"revision" => 0},
                      occurred_at: %DateTime{}
                    } = baseline}

    assert call_id == plan.call_id
    assert room_id == plan.room_id
    assert baseline_sections["customer"].value["id"] == "customer-1"
    assert baseline_sections["intake"].value == nil
    refute inspect(baseline) =~ "customer-1"
    send(baseline_writer, {:test_archive_write_result, :ok})

    assert {:ok, command} =
             update_command(identity,
               section: "intake",
               expected_revision: 0,
               operation: {:merge, %{"summary" => "Ready"}}
             )

    assert {:ok, %{"revision" => 1}} = CallVariables.update(server, command)

    assert_receive {:test_archive_write, update_writer,
                    %UpdateSnapshot{
                      id: "vsnap_" <> _,
                      command_id: command_id,
                      tenant_id: "tenant-demo",
                      call_id: ^call_id,
                      room_id: room_id,
                      incarnation_id: "rinc-test",
                      participant_id: participant_id,
                      activation_id: "act-test",
                      source_participant_id: "part-caller",
                      correlation_id: "corr-test",
                      tool_call_id: "tool-call-test",
                      section: "intake",
                      section_revision: 1,
                      global_revision: 1,
                      sections: sections,
                      source_policy: %{"revision" => 0},
                      occurred_at: %DateTime{}
                    } = snapshot}

    assert command_id == command.id
    assert room_id == Keyword.fetch!(identity, :room_id)
    assert participant_id == Keyword.fetch!(identity, :participant_id)

    assert sections["customer"].value["id"] == "customer-1"
    assert sections["intake"].value == %{"summary" => "Ready"}
    assert sections["intake"].revision == 1
    refute inspect(snapshot) =~ "customer-1"
    refute inspect(:sys.get_state(server)) =~ "customer-1"
    send(update_writer, {:test_archive_write_result, :ok})
    assert eventually(fn -> Handoff.stats(handoff).pending == 0 end)
    assert %{accepted: 2, overflow: 0} = Handoff.stats(handoff)
  end

  test "keeps an accepted variable update local when the bounded archive is full" do
    handoff = open_archive(maximum_pending_facts: 1)
    %{server: server, identity: identity} = start_variables(archive_handoff: handoff)

    assert_receive {:test_archive_write, baseline_writer, %BaselineSnapshot{}}

    assert {:ok, command} =
             update_command(identity,
               section: "intake",
               expected_revision: 0,
               operation: {:put, "summary", "Accepted while storage is stalled"}
             )

    assert {:ok, %{"revision" => 1, "global_revision" => 1}} =
             CallVariables.update(server, command)

    assert %{accepted: 1, overflow: 1, pending: 1, incomplete?: true} =
             Handoff.stats(handoff)

    send(baseline_writer, {:test_archive_write_result, :ok})
    refute_receive {:test_archive_write, _writer, %UpdateSnapshot{}}, 50
  end

  test "serializes competing updates so only one matching revision succeeds" do
    %{server: server, identity: identity} = start_variables()

    commands =
      for priority <- [1, 2] do
        assert {:ok, command} =
                 update_command(identity,
                   section: "intake",
                   expected_revision: 0,
                   operation: {:put, "priority", priority},
                   tool_call_id: "tool-call-#{priority}"
                 )

        command
      end

    results =
      commands
      |> Task.async_stream(&CallVariables.update(server, &1),
        ordered: false,
        timeout: :infinity,
        max_concurrency: 2
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, %{"revision" => 1}}, &1)) == 1

    assert Enum.count(
             results,
             &match?({:error, %Error{code: :call_variables_revision_conflict}}, &1)
           ) == 1
  end

  test "finishes an accepted queued update after its originating caller terminates" do
    handoff = open_archive()
    %{server: server, identity: identity} = start_variables(archive_handoff: handoff)

    assert_receive {:test_archive_write, baseline_writer, %BaselineSnapshot{}}
    send(baseline_writer, {:test_archive_write_result, :ok})
    assert eventually(fn -> Handoff.stats(handoff).pending == 0 end)

    assert {:ok, command} =
             update_command(identity,
               section: "intake",
               expected_revision: 0,
               operation: {:put, "summary", "Finish independently"}
             )

    :ok = :sys.suspend(server)
    task_supervisor = start_supervised!(Task.Supervisor)
    test_process = self()

    task =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        send(test_process, {:call_variables_update_ready, self()})

        receive do
          :begin_call_variables_update -> CallVariables.update(server, command)
        end
      end)

    assert_receive {:call_variables_update_ready, task_pid}
    assert :erlang.trace(task_pid, true, [:send]) == 1
    send(task_pid, :begin_call_variables_update)

    assert_receive {:trace, ^task_pid, :send,
                    {:"$gen_call", {_caller, _tag}, {:update, ^command}}, ^server},
                   5_000

    try do
      monitor = Process.monitor(task.pid)
      Process.exit(task.pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, _pid, :killed}
    after
      :ok = :sys.resume(server)
    end

    assert_receive {:test_archive_write, update_writer,
                    %UpdateSnapshot{
                      section: "intake",
                      section_revision: 1,
                      sections: %{
                        "intake" => %{value: %{"summary" => "Finish independently"}}
                      }
                    }}

    send(update_writer, {:test_archive_write_result, :ok})
  end

  defp start_variables(options \\ []) do
    plan = resolved_plan()
    incarnation_id = "rinc-test"

    child =
      {CallVariables, [plan: plan, incarnation_id: incarnation_id, register: false] ++ options}

    server = start_supervised!(child, significant: false)

    participant = plan.participants["reception"]

    %{
      server: server,
      plan: plan,
      identity: [
        tenant_id: plan.tenant_id,
        room_id: plan.room_id,
        incarnation_id: incarnation_id,
        participant_id: participant.participant_id
      ]
    }
  end

  defp open_archive(options \\ []) do
    options =
      Keyword.merge(
        [
          writer: {TestArchiveWriter, self()},
          maximum_pending_facts: 4,
          retry_delay_ms: 5,
          drain_timeout_ms: 1_000
        ],
        options
      )

    assert {:ok, handoff} = ArchiveSupervisor.open(options)

    on_exit(fn ->
      if Process.alive?(handoff.subscriber) do
        Handoff.source_stopped(handoff, :test_cleanup)
      end
    end)

    handoff
  end

  defp update_command(identity, options) do
    UpdateCallVariables.new(
      identity ++
        options ++
        [
          activation_id: "act-test",
          source_participant_id: "part-caller",
          correlation_id: "corr-test",
          tool_call_id: Keyword.get(options, :tool_call_id, "tool-call-test"),
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

  defp eventually(predicate, attempts \\ 100)

  defp eventually(predicate, attempts) when attempts > 0 do
    if predicate.() do
      true
    else
      Process.sleep(5)
      eventually(predicate, attempts - 1)
    end
  end

  defp eventually(_predicate, 0), do: false
end
