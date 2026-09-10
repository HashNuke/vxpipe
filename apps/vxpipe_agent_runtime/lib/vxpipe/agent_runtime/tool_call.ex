defmodule Vxpipe.AgentRuntime.ToolCall do
  @moduledoc "A complete provider-requested tool call."

  @derive {Inspect, only: [:id, :name]}
  @enforce_keys [:id, :name, :arguments]
  defstruct @enforce_keys ++ [provider_metadata: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          arguments: map(),
          provider_metadata: map()
        }

  @maximum_identifier_bytes 256
  @maximum_name_bytes 128
  @maximum_arguments_bytes 64 * 1_024

  @spec new(keyword()) :: {:ok, t()} | {:error, atom()}
  def new(attributes) when is_list(attributes) do
    with {:ok, attributes} <-
           Keyword.validate(attributes, [:id, :name, :arguments, provider_metadata: %{}]),
         {:ok, id} <- validate_string(Keyword.get(attributes, :id), @maximum_identifier_bytes),
         {:ok, name} <- validate_string(Keyword.get(attributes, :name), @maximum_name_bytes),
         {:ok, arguments} <- validate_arguments(Keyword.get(attributes, :arguments)),
         provider_metadata when is_map(provider_metadata) <-
           Keyword.fetch!(attributes, :provider_metadata) do
      {:ok,
       %__MODULE__{
         id: id,
         name: name,
         arguments: arguments,
         provider_metadata: provider_metadata
       }}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_tool_call}
    end
  end

  def new(_attributes), do: {:error, :invalid_tool_call}

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = call) do
    match?({:ok, _value}, validate_string(call.id, @maximum_identifier_bytes)) and
      match?({:ok, _value}, validate_string(call.name, @maximum_name_bytes)) and
      match?({:ok, _value}, validate_arguments(call.arguments)) and
      is_map(call.provider_metadata)
  end

  def valid?(_call), do: false

  defp validate_string(value, maximum_bytes)
       when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= maximum_bytes,
       do: {:ok, value}

  defp validate_string(_value, _maximum_bytes), do: {:error, :invalid_tool_call}

  defp validate_arguments(arguments) when is_map(arguments) do
    if :erlang.external_size(arguments) <= @maximum_arguments_bytes do
      {:ok, arguments}
    else
      {:error, :arguments_too_large}
    end
  end

  defp validate_arguments(_arguments), do: {:error, :invalid_tool_call}
end
