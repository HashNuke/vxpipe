defmodule Vxpipe.Providers.Google.STSAgentConfig do
  @moduledoc false

  alias Vxpipe.AgentRuntime.ToolDescriptor

  def validate(prompt, tools) do
    with true <- is_binary(prompt) and byte_size(prompt) <= 65_536 and String.valid?(prompt),
         true <- is_list(tools) and length(tools) <= 64,
         true <- :erlang.external_size({prompt, tools}) <= 131_072,
         true <- Enum.all?(tools, &valid_tool?/1),
         names = Enum.map(tools, &Map.fetch!(&1, "name")),
         true <- Enum.uniq(names) == names,
         encoded = JSON.encode!(%{"prompt" => prompt, "tools" => tools}),
         true <- byte_size(encoded) <= 131_072 do
      :ok
    else
      _invalid -> {:error, :invalid_configuration}
    end
  rescue
    _exception -> {:error, :invalid_configuration}
  end

  defp valid_tool?(
         %{
           "name" => name,
           "description" => description,
           "parametersJsonSchema" => %{"type" => "object"} = schema
         } = tool
       )
       when map_size(tool) == 3 do
    with true <- JSON.decode!(JSON.encode!(schema)) == schema,
         {:ok, _descriptor} <-
           ToolDescriptor.new(
             name: name,
             description: description,
             input_schema: schema,
             binding: :configuration
           ) do
      true
    else
      _invalid -> false
    end
  end

  defp valid_tool?(_tool), do: false
end
