defmodule Vxpipe.CallEngine.CallVariables.WriteSchema do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.VariableSchema
  alias Vxpipe.CallEngine.Tool.{UpdateVariable, UpdateVariables}

  def details(tool_name, arguments, writable_schemas) do
    name = arguments["section_name"] || arguments[:section_name]
    field = arguments["variable_name"] || arguments[:variable_name]
    envelope = envelope(tool_name)

    case Map.fetch(writable_schemas, name) do
      {:ok, schema} ->
        target = put_in(envelope, ["properties", "section_name"], %{"const" => name})
        specialize(tool_name, field, target, VariableSchema.write_schema(schema))

      :error ->
        details("/section_name", envelope)
    end
  end

  defp specialize("update_variables", _field, target, schema) do
    details("/data", put_in(target, ["properties", "data"], schema))
  end

  defp specialize("update_variable", field, target, schema) do
    properties = Map.get(schema, "properties", %{})

    case Map.fetch(properties, field) do
      {:ok, field_schema} ->
        expected =
          target
          |> put_in(["properties", "variable_name"], %{"const" => field})
          |> put_in(["properties", "variable_value"], field_schema)

        details("/variable_value", expected)

      :error ->
        names = properties |> Map.keys() |> Enum.sort()

        details(
          "/variable_name",
          put_in(target, ["properties", "variable_name"], %{"enum" => names})
        )
    end
  end

  defp envelope("update_variable"), do: UpdateVariable.definition().parameters
  defp envelope("update_variables"), do: UpdateVariables.definition().parameters

  defp details(path, expected), do: %{"argument_path" => path, "expected_schema" => expected}
end
