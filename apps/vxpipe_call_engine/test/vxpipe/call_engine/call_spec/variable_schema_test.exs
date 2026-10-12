defmodule Vxpipe.CallEngine.CallSpec.VariableSchemaTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.VariableSchema

  test "variables, nested fields and array items accept null by default, including enums" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "name" => %{"type" => "string", "minLength" => 2},
        "age" => %{"type" => "integer", "minimum" => 1, "enum" => [18, 21]},
        "profile" => %{
          "type" => "object",
          "properties" => %{"active" => %{"type" => "boolean"}},
          "additionalProperties" => false
        },
        "scores" => %{"type" => "array", "items" => %{"type" => "number"}}
      },
      "required" => ["name"],
      "additionalProperties" => false
    }

    assert {:ok, validator} = VariableSchema.compile(schema, ["schema"])

    assert {:ok, _} =
             JSV.validate(
               %{"name" => nil, "age" => nil, "profile" => nil, "scores" => nil},
               validator
             )

    assert {:ok, _} =
             JSV.validate(%{"profile" => %{"active" => nil}, "scores" => [nil, 2]}, validator)

    assert {:error, _} = JSV.validate(%{"age" => 19}, validator)
    assert {:error, _} = JSV.validate(%{"age" => "18"}, validator)
    assert {:error, _} = JSV.validate(nil, validator)
  end

  test "JSON authors can explicitly opt out of the nullable default" do
    schema = %{
      "type" => "object",
      "properties" => %{"name" => %{"type" => "string", "nullable" => false}}
    }

    assert {:ok, validator} = VariableSchema.compile(schema, ["schema"])
    assert {:error, _} = JSV.validate(%{"name" => nil}, validator)
    assert {:ok, _} = JSV.validate(%{"name" => "John"}, validator)
    invalid = put_in(schema, ["properties", "name", "nullable"], "yes")
    assert {:error, error} = VariableSchema.compile(invalid, ["schema"])
    assert error.details["path"] == ["schema", "properties", "name", "nullable"]
  end
end
