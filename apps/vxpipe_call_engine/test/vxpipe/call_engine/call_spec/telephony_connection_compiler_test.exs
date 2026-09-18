defmodule Vxpipe.CallEngine.CallDefinition.TelephonyConnectionCompilerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallDefinition
  alias Vxpipe.CallEngine.CallDefinition.NumberFromVariable
  alias Vxpipe.CallEngine.Error

  test "accepts provider-neutral receive and literal dial connection intents" do
    input =
      base_definition()
      |> put_in([:participants, "caller", :connection], %{
        service: "primary-phone",
        mode: "receive",
        number: "+15550001000",
        admission: "start_call"
      })
      |> put_in([:participants, "reception", :transfers], ["human-support"])
      |> put_in([:participants, "human-support"], %{
        type: "human",
        description: "A human support specialist",
        connection: %{
          service: "primary-phone",
          mode: "dial",
          number: "+15550001001"
        }
      })

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "support", revision: 1)

    assert %{
             service: "primary-phone",
             mode: :receive,
             admission: :start_call,
             number: "+15550001000",
             number_from_variable: nil
           } = definition.participants["caller"].connection

    assert %{
             service: "primary-phone",
             mode: :dial,
             admission: :transfer,
             number: "+15550001001",
             number_from_variable: nil
           } = definition.participants["human-support"].connection
  end

  test "accepts a protected string variable as the dial destination" do
    input =
      base_definition()
      |> put_in([:participants, "reception", :transfers], ["human-support"])
      |> put_in([:participants, "reception", :variable_permissions], %{
        "routing" => ["read"]
      })
      |> put_in([:participants, "human-support"], %{
        type: "human",
        connection: %{
          service: "primary-phone",
          mode: "dial",
          number_from_variable: %{
            section: "routing",
            variable: "support_number"
          }
        }
      })

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "support", revision: 1)

    assert %NumberFromVariable{section: "routing", variable: "support_number"} =
             definition.participants["human-support"].connection.number_from_variable
  end

  test "rejects ambiguous, absent, misplaced, and malformed phone destinations" do
    base =
      base_definition()
      |> put_in([:participants, "reception", :transfers], ["human-support"])
      |> put_in([:participants, "human-support"], %{
        type: "human",
        connection: %{
          service: "primary-phone",
          mode: "dial",
          number: "+15550001001"
        }
      })

    cases = [
      {put_in(base, [:participants, "human-support", :connection, :number], "555-0001"),
       ["participants", "human-support", "connection", "number"]},
      {base
       |> update_in([:participants, "human-support", :connection], &Map.delete(&1, :number)),
       ["participants", "human-support", "connection", "number"]},
      {put_in(base, [:participants, "human-support", :connection, :number_from_variable], %{
         section: "routing",
         variable: "support_number"
       }), ["participants", "human-support", "connection", "number_from_variable"]},
      {base
       |> put_in([:participants, "human-support", :connection, :mode], "receive")
       |> put_in([:participants, "human-support", :connection, :admission], "transfer")
       |> put_in(
         [:participants, "human-support", :connection, :number_from_variable],
         %{section: "routing", variable: "support_number"}
       )
       |> update_in([:participants, "human-support", :connection], &Map.delete(&1, :number)),
       ["participants", "human-support", "connection", "number_from_variable"]},
      {base
       |> put_in([:participants, "human-support", :connection, :admission], "start_call"),
       ["participants", "human-support", "connection", "admission"]}
    ]

    for {input, path} <- cases do
      assert {:error,
              %Error{
                code: :invalid_call_definition,
                details: %{"path" => ^path}
              }} = CallDefinition.new(input, resource_id: "support", revision: 1)
    end
  end

  test "rejects an undeclared, non-string, or agent-writable routing variable" do
    dynamic = dynamic_definition()

    cases = [
      {put_in(
         dynamic,
         [:participants, "human-support", :connection, :number_from_variable, :section],
         "missing"
       ), ["participants", "human-support", "connection", "number_from_variable", "section"]},
      {put_in(
         dynamic,
         [:participants, "human-support", :connection, :number_from_variable, :variable],
         "missing"
       ), ["participants", "human-support", "connection", "number_from_variable", "variable"]},
      {put_in(
         dynamic,
         [:call_variables, :sections, "routing", :schema, "properties", "support_number", "type"],
         "integer"
       ), ["participants", "human-support", "connection", "number_from_variable", "variable"]},
      {put_in(dynamic, [:participants, "reception", :variable_permissions], %{
         "routing" => ["read", "write"]
       }), ["participants", "reception", "variable_permissions", "routing"]}
    ]

    for {input, path} <- cases do
      assert {:error,
              %Error{
                code: :invalid_call_definition,
                details: %{"path" => ^path}
              }} = CallDefinition.new(input, resource_id: "support", revision: 1)
    end
  end

  defp dynamic_definition do
    base_definition()
    |> put_in([:participants, "reception", :transfers], ["human-support"])
    |> put_in([:participants, "human-support"], %{
      type: "human",
      connection: %{
        service: "primary-phone",
        mode: "dial",
        number_from_variable: %{section: "routing", variable: "support_number"}
      }
    })
  end

  defp base_definition do
    %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "reception",
      call_variables: %{
        sections: %{
          "routing" => %{
            schema: %{
              "type" => "object",
              "properties" => %{
                "support_number" => %{"type" => ["string", "null"]}
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
          prompt: "Route the caller safely.",
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
