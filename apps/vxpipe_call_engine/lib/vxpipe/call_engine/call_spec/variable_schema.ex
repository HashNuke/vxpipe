defmodule Vxpipe.CallEngine.CallDefinition.VariableSchema do
  @moduledoc false

  alias Vxpipe.CallEngine.DefinitionValidation

  @keywords [
    "additionalProperties",
    "enum",
    "exclusiveMaximum",
    "exclusiveMinimum",
    "items",
    "maxItems",
    "maxLength",
    "maximum",
    "minItems",
    "minLength",
    "minimum",
    "properties",
    "required",
    "type"
  ]
  @types ["array", "boolean", "integer", "null", "number", "object", "string"]
  @non_negative_integer_keywords ["maxItems", "maxLength", "minItems", "minLength"]
  @number_keywords ["exclusiveMaximum", "exclusiveMinimum", "maximum", "minimum"]

  @spec compile(term(), [String.t()]) ::
          {:ok, JSV.Root.t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def compile(schema, path) do
    with :ok <- validate_json(schema, path),
         :ok <- validate_root(schema, path),
         :ok <- validate_node(schema, path),
         {:ok, validator} <- build(relax_required(schema), path) do
      {:ok, validator}
    end
  end

  defp validate_json(value, path) when is_map(value) do
    Enum.reduce_while(value, :ok, fn
      {key, nested}, :ok when is_binary(key) ->
        continue(validate_json(nested, path ++ [key]))

      {_key, _nested}, :ok ->
        {:halt, invalid(path, "schema keys must be strings")}
    end)
  end

  defp validate_json(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {nested, index}, :ok ->
      continue(validate_json(nested, path ++ [Integer.to_string(index)]))
    end)
  end

  defp validate_json(value, _path)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: :ok

  defp validate_json(_value, path), do: invalid(path, "must contain only JSON values")

  defp validate_root(%{"type" => "object"}, _path), do: :ok
  defp validate_root(_schema, path), do: invalid(path ++ ["type"], "must be object")

  defp validate_node(schema, path) when is_map(schema) do
    with :ok <- validate_keywords(schema, path),
         :ok <- validate_type(Map.get(schema, "type"), path),
         :ok <- validate_required(Map.get(schema, "required", []), path),
         :ok <- validate_additional_properties(schema, path),
         :ok <- validate_enum(schema, path),
         :ok <- validate_bounds(schema, path),
         :ok <- validate_properties(Map.get(schema, "properties", %{}), path),
         :ok <- validate_items(schema, path) do
      :ok
    end
  end

  defp validate_node(_schema, path), do: invalid(path, "must be an object schema")

  defp validate_keywords(schema, path) do
    case Enum.find(Map.keys(schema), &(&1 not in @keywords)) do
      nil -> :ok
      keyword -> invalid(path ++ [keyword], "is not supported in Call Variables schemas")
    end
  end

  defp validate_type(nil, _path), do: :ok
  defp validate_type(type, _path) when type in @types, do: :ok

  defp validate_type(types, path) when is_list(types) do
    unique = Enum.uniq(types)

    if length(types) == 2 and length(unique) == 2 and "null" in types and
         Enum.all?(types, &(&1 in @types)) do
      :ok
    else
      invalid(path ++ ["type"], "must be one supported type or one nullable type")
    end
  end

  defp validate_type(_type, path) do
    invalid(path ++ ["type"], "must be one supported type or one nullable type")
  end

  defp validate_required(required, _path) when required == [], do: :ok

  defp validate_required(required, path) when is_list(required) do
    if Enum.all?(required, &is_binary/1) and length(Enum.uniq(required)) == length(required) do
      :ok
    else
      invalid(path ++ ["required"], "must contain unique string names")
    end
  end

  defp validate_required(_required, path) do
    invalid(path ++ ["required"], "must be an array of unique string names")
  end

  defp validate_additional_properties(schema, path) do
    case Map.fetch(schema, "additionalProperties") do
      :error -> :ok
      {:ok, false} -> :ok
      {:ok, _value} -> invalid(path ++ ["additionalProperties"], "must be false")
    end
  end

  defp validate_enum(schema, path) do
    case Map.fetch(schema, "enum") do
      :error ->
        :ok

      {:ok, values} when is_list(values) and values != [] ->
        if length(Enum.uniq(values)) == length(values) do
          :ok
        else
          invalid(path ++ ["enum"], "must contain unique JSON values")
        end

      {:ok, _values} ->
        invalid(path ++ ["enum"], "must be a non-empty array")
    end
  end

  defp validate_bounds(schema, path) do
    with :ok <- validate_non_negative_integer_bounds(schema, path),
         :ok <- validate_number_bounds(schema, path) do
      :ok
    end
  end

  defp validate_non_negative_integer_bounds(schema, path) do
    Enum.reduce_while(@non_negative_integer_keywords, :ok, fn keyword, :ok ->
      case Map.fetch(schema, keyword) do
        :error -> {:cont, :ok}
        {:ok, value} when is_integer(value) and value >= 0 -> {:cont, :ok}
        {:ok, _value} -> {:halt, invalid(path ++ [keyword], "must be a non-negative integer")}
      end
    end)
  end

  defp validate_number_bounds(schema, path) do
    Enum.reduce_while(@number_keywords, :ok, fn keyword, :ok ->
      case Map.fetch(schema, keyword) do
        :error -> {:cont, :ok}
        {:ok, value} when is_number(value) -> {:cont, :ok}
        {:ok, _value} -> {:halt, invalid(path ++ [keyword], "must be a number")}
      end
    end)
  end

  defp validate_properties(properties, path) when is_map(properties) do
    Enum.reduce_while(properties, :ok, fn
      {name, schema}, :ok when is_binary(name) ->
        continue(validate_node(schema, path ++ ["properties", name]))

      {_name, _schema}, :ok ->
        {:halt, invalid(path ++ ["properties"], "variable names must be strings")}
    end)
  end

  defp validate_properties(_properties, path) do
    invalid(path ++ ["properties"], "must be an object")
  end

  defp validate_items(schema, path) do
    case Map.fetch(schema, "items") do
      :error -> :ok
      {:ok, items} -> validate_node(items, path ++ ["items"])
    end
  end

  defp build(schema, path) do
    case JSV.build(schema, atoms: false, resolver: [], warnings: :silent) do
      {:ok, validator} -> {:ok, validator}
      {:error, _error} -> invalid(path, "must be a valid supported JSON Schema")
    end
  end

  defp relax_required(schema) do
    schema
    |> Map.delete("required")
    |> relax_properties()
    |> relax_items()
  end

  defp relax_properties(schema) do
    case Map.fetch(schema, "properties") do
      {:ok, properties} ->
        Map.put(
          schema,
          "properties",
          Map.new(properties, fn {name, node} ->
            {name, relax_required(node)}
          end)
        )

      :error ->
        schema
    end
  end

  defp relax_items(schema) do
    case Map.fetch(schema, "items") do
      {:ok, items} -> Map.put(schema, "items", relax_required(items))
      :error -> schema
    end
  end

  defp continue(:ok), do: {:cont, :ok}
  defp continue({:error, _error} = error), do: {:halt, error}

  defp invalid(path, reason) do
    DefinitionValidation.invalid(
      :invalid_call_definition,
      "The call definition is invalid.",
      path,
      reason
    )
  end
end
