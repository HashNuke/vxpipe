defmodule Vxpipe.AgentRuntime.ToolRegistry do
  @moduledoc "An activation-pinned registry of model projections and private tool bindings."

  alias Vxpipe.AgentRuntime.{ModelTool, ToolDescriptor}

  @derive {Inspect, only: [:size]}
  @enforce_keys [:by_name, :model_tools, :size]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          by_name: %{String.t() => ToolDescriptor.t()},
          model_tools: [ModelTool.t()],
          size: non_neg_integer()
        }

  @default_maximum_tools 64

  @spec new([ToolDescriptor.t()], keyword()) :: {:ok, t()} | {:error, atom()}
  def new(descriptors, options \\ [])

  def new(descriptors, options) when is_list(descriptors) and is_list(options) do
    with {:ok, options} <- Keyword.validate(options, maximum_tools: @default_maximum_tools),
         maximum_tools when is_integer(maximum_tools) and maximum_tools > 0 <-
           Keyword.fetch!(options, :maximum_tools),
         false <- length(descriptors) > maximum_tools,
         {:ok, registry} <- build(descriptors) do
      {:ok, registry}
    else
      true -> {:error, :too_many_tools}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_registry}
    end
  end

  def new(_descriptors, _options), do: {:error, :invalid_registry}

  @spec model_tools(t()) :: [ModelTool.t()]
  def model_tools(%__MODULE__{} = registry), do: registry.model_tools

  @spec resolve(t(), String.t(), map()) ::
          {:ok, ToolDescriptor.t()} | {:error, :invalid_arguments | :unknown_tool}
  def resolve(%__MODULE__{} = registry, name, arguments)
      when is_binary(name) and is_map(arguments) do
    with {:ok, descriptor} <- Map.fetch(registry.by_name, name),
         {:ok, _validated} <- JSV.validate(arguments, descriptor.compiled_schema, cast: false) do
      {:ok, descriptor}
    else
      :error -> {:error, :unknown_tool}
      {:error, _validation_error} -> {:error, :invalid_arguments}
    end
  end

  def resolve(%__MODULE__{}, _name, _arguments), do: {:error, :invalid_arguments}

  defp build(descriptors) do
    Enum.reduce_while(descriptors, {:ok, %{}, []}, fn descriptor, {:ok, by_name, tools} ->
      case add_descriptor(descriptor, by_name, tools) do
        {:ok, by_name, tools} -> {:cont, {:ok, by_name, tools}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, by_name, tools} ->
        {:ok,
         %__MODULE__{
           by_name: by_name,
           model_tools: Enum.reverse(tools),
           size: map_size(by_name)
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp add_descriptor(%ToolDescriptor{} = descriptor, by_name, tools) do
    if Map.has_key?(by_name, descriptor.name) do
      {:error, :duplicate_tool}
    else
      {:ok, Map.put(by_name, descriptor.name, descriptor),
       [ModelTool.from_descriptor(descriptor) | tools]}
    end
  end

  defp add_descriptor(_descriptor, _by_name, _tools), do: {:error, :invalid_descriptor}
end
