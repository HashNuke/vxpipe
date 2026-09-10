defmodule Vxpipe.CallEngine.CallDefinition.CallVariablesCompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallDefinition
  alias Vxpipe.CallEngine.CallDefinition.VariableSection
  alias Vxpipe.CallEngine.CallInvocation
  alias Vxpipe.CallEngine.DefinitionCompiler
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.ResolvedCallPlan

  @schema_version "20260910.06"

  test "compiles partial initial values and agent permissions into typed plan state" do
    assert {:ok, definition} =
             CallDefinition.new(definition_input(), resource_id: "support", revision: 1)

    assert %VariableSection{name: "customer", schema: schema} =
             definition.call_variables.sections["customer"]

    assert schema["required"] == ["id", "profile"]

    assert definition.participants["reception"].variable_permissions.grants == %{
             "customer" => :read,
             "intake" => :read_write
           }

    invocation_input = %{
      call_definition: %{id: "support", revision: 1},
      initial_variables: %{
        "customer" => %{
          "id" => "customer-1",
          "profile" => %{"city" => "Exampleville"}
        }
      },
      transport: %{type: "web"}
    }

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input,
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, %ResolvedCallPlan{} = plan} =
             DefinitionCompiler.compile(definition, invocation, registries())

    assert plan.call_variables.sections["customer"].value == %{
             "id" => "customer-1",
             "profile" => %{"city" => "Exampleville"}
           }

    assert plan.call_variables.sections["customer"].revision == 0
    assert plan.call_variables.sections["intake"].value == nil
    assert plan.call_variables.sections["intake"].revision == 0

    assert plan.participants["reception"].variable_permissions.grants == %{
             "customer" => :read,
             "intake" => :read_write
           }
  end

  test "accepts equivalent JSON and Elixir variable definitions and invocations" do
    definition_input = definition_input()

    assert {:ok, elixir_definition} =
             CallDefinition.new(definition_input, resource_id: "support", revision: 1)

    assert {:ok, json_definition} =
             definition_input
             |> JSON.encode!()
             |> CallDefinition.from_json(resource_id: "support", revision: 1)

    assert elixir_definition == json_definition

    invocation_input = %{
      call_definition: %{id: "support", revision: 1},
      initial_variables: %{"customer" => %{"id" => "customer-1"}},
      transport: %{type: "web"}
    }

    trusted = [
      tenant_id: "tenant-demo",
      actor_id: "actor-demo",
      call_id: "call-1",
      room_id: "room-1"
    ]

    assert {:ok, elixir_invocation} = CallInvocation.new(invocation_input, trusted)

    assert {:ok, json_invocation} =
             invocation_input
             |> JSON.encode!()
             |> CallInvocation.from_json(trusted)

    assert elixir_invocation == json_invocation
  end

  test "rejects defaults anywhere in a variable schema without returning the value" do
    input =
      put_in(
        definition_input(),
        [
          :call_variables,
          :sections,
          "customer",
          :schema,
          "properties",
          "profile",
          "properties",
          "city",
          "default"
        ],
        "private-city"
      )

    assert {:error,
            %Error{
              code: :invalid_call_definition,
              details: %{
                "path" => [
                  "call_variables",
                  "sections",
                  "customer",
                  "schema",
                  "properties",
                  "profile",
                  "properties",
                  "city",
                  "default"
                ]
              }
            } = error} = CallDefinition.new(input, resource_id: "support", revision: 1)

    refute inspect(error) =~ "private-city"
  end

  test "rejects invalid or unsupported variable schemas before compilation" do
    cases = [
      {put_in(
         definition_input(),
         [:call_variables, :sections, "customer", :schema, "type"],
         "array"
       ), ["call_variables", "sections", "customer", "schema", "type"]},
      {put_in(
         definition_input(),
         [:call_variables, :sections, "customer", :schema, "properties", "id", "type"],
         "not-a-json-schema-type"
       ), ["call_variables", "sections", "customer", "schema", "properties", "id", "type"]},
      {put_in(
         definition_input(),
         [:call_variables, :sections, "customer", :schema, "required"],
         "id"
       ), ["call_variables", "sections", "customer", "schema", "required"]},
      {put_in(
         definition_input(),
         [:call_variables, :sections, "customer", :schema, "allOf"],
         []
       ), ["call_variables", "sections", "customer", "schema", "allOf"]},
      {put_in(
         definition_input(),
         [:call_variables, :sections, "customer", :schema, "$ref"],
         "https://example.invalid/schema"
       ), ["call_variables", "sections", "customer", "schema", "$ref"]}
    ]

    for {input, path} <- cases do
      assert {:error, %Error{code: :invalid_call_definition, details: %{"path" => ^path}}} =
               CallDefinition.new(input, resource_id: "support", revision: 1)
    end
  end

  test "rejects invalid or unknown agent variable permissions" do
    cases = [
      {%{"customer" => ["write"]},
       ["participants", "reception", "variable_permissions", "customer"]},
      {%{"customer" => ["read", "admin"]},
       ["participants", "reception", "variable_permissions", "customer"]},
      {%{"unknown" => ["read"]},
       ["participants", "reception", "variable_permissions", "unknown"]},
      {%{"customer" => ["read", "read"]},
       ["participants", "reception", "variable_permissions", "customer"]}
    ]

    for {permissions, path} <- cases do
      input =
        put_in(
          definition_input(),
          [:participants, "reception", :variable_permissions],
          permissions
        )

      assert {:error, %Error{code: :invalid_call_definition, details: %{"path" => ^path}}} =
               CallDefinition.new(input, resource_id: "support", revision: 1)
    end
  end

  test "rejects unknown sections and invalid populated values before room startup" do
    invalid_values = [
      {%{"unknown" => %{}}, ["initial_variables", "unknown"]},
      {%{"customer" => "not-an-object"}, ["initial_variables", "customer"]},
      {%{"customer" => %{"id" => 123}}, ["initial_variables", "customer"]},
      {%{"customer" => %{"unknown" => true}}, ["initial_variables", "customer"]}
    ]

    assert {:ok, definition} =
             CallDefinition.new(definition_input(), resource_id: "support", revision: 1)

    for {initial_variables, path} <- invalid_values do
      invocation_input = %{
        call_definition: %{id: "support", revision: 1},
        initial_variables: initial_variables,
        transport: %{type: "web"}
      }

      assert {:ok, invocation} =
               CallInvocation.new(invocation_input,
                 tenant_id: "tenant-demo",
                 actor_id: "actor-demo"
               )

      assert {:error,
              %Error{code: :call_definition_resolution_failed, details: %{"path" => ^path}}} =
               DefinitionCompiler.compile(definition, invocation, registries())
    end
  end

  test "allows explicit empty sections and does not fill schema-required variables" do
    assert {:ok, definition} =
             CallDefinition.new(definition_input(), resource_id: "support", revision: 1)

    invocation_input = %{
      call_definition: %{id: "support", revision: 1},
      initial_variables: %{"customer" => %{}},
      transport: %{type: "web"}
    }

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input,
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries())
    assert plan.call_variables.sections["customer"].value == %{}
    assert plan.call_variables.sections["intake"].value == nil
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
                "id" => %{"type" => "string", "minLength" => 1},
                "profile" => %{
                  "type" => "object",
                  "properties" => %{
                    "city" => %{"type" => "string"},
                    "postal_code" => %{"type" => "string"}
                  },
                  "required" => ["city", "postal_code"],
                  "additionalProperties" => false
                }
              },
              "required" => ["id", "profile"],
              "additionalProperties" => false
            }
          },
          "intake" => %{
            schema: %{
              "type" => "object",
              "properties" => %{
                "summary" => %{"type" => "string"},
                "priority" => %{"type" => "integer"}
              },
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
end
