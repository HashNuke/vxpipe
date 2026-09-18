defmodule Vxpipe.CallEngine.CallSpec.CallVariablesCompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec
  alias Vxpipe.CallEngine.CallSpec.VariableSection
  alias Vxpipe.CallEngine.CallInvocation
  alias Vxpipe.CallEngine.CallSpecCompiler
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.ResolvedCallPlan

  @schema_version "20260915.01"

  test "compiles partial initial values and agent permissions into typed plan state" do
    assert {:ok, call_spec} =
             CallSpec.new(call_spec_input(), resource_id: "support", revision: 1)

    assert %VariableSection{name: "customer", schema: schema} =
             call_spec.call_variables.sections["customer"]

    assert schema["required"] == ["id", "profile"]

    assert call_spec.participants["reception"].variable_permissions.grants == %{
             "customer" => :read,
             "intake" => :read_write
           }

    invocation_input = %{
      call_spec: %{id: "support", revision: 1},
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
             CallSpecCompiler.compile(call_spec, invocation, registries())

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

  test "accepts equivalent JSON and Elixir variable call specs and invocations" do
    call_spec_input = call_spec_input()

    assert {:ok, elixir_call_spec} =
             CallSpec.new(call_spec_input, resource_id: "support", revision: 1)

    assert {:ok, json_call_spec} =
             call_spec_input
             |> JSON.encode!()
             |> CallSpec.from_json(resource_id: "support", revision: 1)

    assert elixir_call_spec == json_call_spec

    invocation_input = %{
      call_spec: %{id: "support", revision: 1},
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
        call_spec_input(),
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
              code: :invalid_call_spec,
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
            } = error} = CallSpec.new(input, resource_id: "support", revision: 1)

    refute inspect(error) =~ "private-city"
  end

  test "rejects invalid or unsupported variable schemas before compilation" do
    cases = [
      {put_in(
         call_spec_input(),
         [:call_variables, :sections, "customer", :schema, "type"],
         "array"
       ), ["call_variables", "sections", "customer", "schema", "type"]},
      {put_in(
         call_spec_input(),
         [:call_variables, :sections, "customer", :schema, "properties", "id", "type"],
         "not-a-json-schema-type"
       ), ["call_variables", "sections", "customer", "schema", "properties", "id", "type"]},
      {put_in(
         call_spec_input(),
         [:call_variables, :sections, "customer", :schema, "required"],
         "id"
       ), ["call_variables", "sections", "customer", "schema", "required"]},
      {put_in(
         call_spec_input(),
         [:call_variables, :sections, "customer", :schema, "allOf"],
         []
       ), ["call_variables", "sections", "customer", "schema", "allOf"]},
      {put_in(
         call_spec_input(),
         [:call_variables, :sections, "customer", :schema, "$ref"],
         "https://example.invalid/schema"
       ), ["call_variables", "sections", "customer", "schema", "$ref"]}
    ]

    for {input, path} <- cases do
      assert {:error, %Error{code: :invalid_call_spec, details: %{"path" => ^path}}} =
               CallSpec.new(input, resource_id: "support", revision: 1)
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
          call_spec_input(),
          [:participants, "reception", :variable_permissions],
          permissions
        )

      assert {:error, %Error{code: :invalid_call_spec, details: %{"path" => ^path}}} =
               CallSpec.new(input, resource_id: "support", revision: 1)
    end
  end

  test "rejects unknown sections and invalid populated values before room startup" do
    invalid_values = [
      {%{"unknown" => %{}}, ["initial_variables", "unknown"]},
      {%{"customer" => "not-an-object"}, ["initial_variables", "customer"]},
      {%{"customer" => %{"id" => 123}}, ["initial_variables", "customer"]},
      {%{"customer" => %{"unknown" => true}}, ["initial_variables", "customer"]}
    ]

    assert {:ok, call_spec} =
             CallSpec.new(call_spec_input(), resource_id: "support", revision: 1)

    for {initial_variables, path} <- invalid_values do
      invocation_input = %{
        call_spec: %{id: "support", revision: 1},
        initial_variables: initial_variables,
        transport: %{type: "web"}
      }

      assert {:ok, invocation} =
               CallInvocation.new(invocation_input,
                 tenant_id: "tenant-demo",
                 actor_id: "actor-demo"
               )

      assert {:error, %Error{code: :call_spec_resolution_failed, details: %{"path" => ^path}}} =
               CallSpecCompiler.compile(call_spec, invocation, registries())
    end
  end

  test "allows explicit empty sections and does not fill schema-required variables" do
    assert {:ok, call_spec} =
             CallSpec.new(call_spec_input(), resource_id: "support", revision: 1)

    invocation_input = %{
      call_spec: %{id: "support", revision: 1},
      initial_variables: %{"customer" => %{}},
      transport: %{type: "web"}
    }

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input,
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, registries())
    assert plan.call_variables.sections["customer"].value == %{}
    assert plan.call_variables.sections["intake"].value == nil
  end

  defp call_spec_input do
    %{
      schema_version: @schema_version,
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "default"}}},
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
      host_tools: %{}
    }
  end
end
