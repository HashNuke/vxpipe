defmodule Vxpipe.MCP.ArgumentValidator do
  @moduledoc false

  @schema_draft_7 "http://json-schema.org/draft-07/schema"
  @schema_2020_12 "https://json-schema.org/draft/2020-12/schema"

  @spec validate(map(), map()) ::
          :ok | {:error, :invalid_arguments | :unsupported_input_schema}
  def validate(schema, arguments) when is_map(schema) and is_map(arguments) do
    with :ok <- supported_dialect(schema),
         false <- external_reference?(schema),
         {:ok, root} <- JSV.build(schema, resolver: [], atoms: false, warnings: :silent),
         {:ok, _validated} <- JSV.validate(arguments, root, cast: false) do
      :ok
    else
      true -> {:error, :unsupported_input_schema}
      {:error, %JSV.ValidationError{}} -> {:error, :invalid_arguments}
      {:error, _build_error} -> {:error, :unsupported_input_schema}
    end
  end

  def validate(_schema, _arguments), do: {:error, :invalid_arguments}

  defp supported_dialect(schema) do
    case Map.get(schema, "$schema") do
      nil -> :ok
      @schema_draft_7 -> :ok
      @schema_draft_7 <> "#" -> :ok
      @schema_2020_12 -> :ok
      @schema_2020_12 <> "#" -> :ok
      _unsupported -> {:error, :unsupported_input_schema}
    end
  end

  defp external_reference?(%{"$ref" => reference})
       when is_binary(reference) and not is_nil(reference) do
    not String.starts_with?(reference, "#")
  end

  defp external_reference?(value) when is_map(value) do
    Enum.any?(value, fn {_key, nested} -> external_reference?(nested) end)
  end

  defp external_reference?(value) when is_list(value),
    do: Enum.any?(value, &external_reference?/1)

  defp external_reference?(_value), do: false
end
