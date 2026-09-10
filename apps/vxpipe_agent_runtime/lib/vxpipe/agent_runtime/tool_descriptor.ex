defmodule Vxpipe.AgentRuntime.ToolDescriptor do
  @moduledoc """
  A model-visible tool description paired with an opaque runtime-only binding.
  """

  @derive {Inspect, only: [:name, :description, :input_schema]}
  @enforce_keys [:name, :description, :input_schema, :binding, :compiled_schema]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map(),
          binding: term(),
          compiled_schema: JSV.Root.t()
        }

  @name_pattern ~r/^[A-Za-z0-9_-]+$/
  @max_name_bytes 128
  @max_description_bytes 1_024
  @max_schema_bytes 64 * 1_024

  @spec new(keyword()) :: {:ok, t()} | {:error, atom()}
  def new(attributes) when is_list(attributes) do
    with {:ok, attributes} <-
           Keyword.validate(attributes, [:name, :description, :input_schema, :binding]),
         {:ok, name} <- validate_name(Keyword.get(attributes, :name)),
         {:ok, description} <- validate_description(Keyword.get(attributes, :description)),
         {:ok, input_schema, compiled_schema} <-
           validate_schema(Keyword.get(attributes, :input_schema)),
         {:ok, binding} <- validate_binding(Keyword.get(attributes, :binding)) do
      {:ok,
       %__MODULE__{
         name: name,
         description: description,
         input_schema: input_schema,
         binding: binding,
         compiled_schema: compiled_schema
       }}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_descriptor}
    end
  end

  def new(_attributes), do: {:error, :invalid_descriptor}

  defp validate_name(name) when is_binary(name) and byte_size(name) <= @max_name_bytes do
    if Regex.match?(@name_pattern, name), do: {:ok, name}, else: {:error, :invalid_name}
  end

  defp validate_name(_name), do: {:error, :invalid_name}

  defp validate_description(description)
       when is_binary(description) and byte_size(description) > 0 and
              byte_size(description) <= @max_description_bytes,
       do: {:ok, description}

  defp validate_description(_description), do: {:error, :invalid_description}

  defp validate_schema(schema)
       when is_map(schema) and map_size(schema) > 0 do
    if :erlang.external_size(schema) <= @max_schema_bytes do
      case JSV.build(schema, warnings: :silent) do
        {:ok, compiled_schema} -> {:ok, schema, compiled_schema}
        {:error, _reason} -> {:error, :invalid_input_schema}
      end
    else
      {:error, :input_schema_too_large}
    end
  end

  defp validate_schema(_schema), do: {:error, :invalid_input_schema}

  defp validate_binding(nil), do: {:error, :invalid_binding}
  defp validate_binding(binding), do: {:ok, binding}
end
