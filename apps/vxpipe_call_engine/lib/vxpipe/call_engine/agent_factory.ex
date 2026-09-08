defmodule Vxpipe.CallEngine.AgentFactory do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.Definition

  @spec configure(GenServer.server(), keyword()) :: :ok | {:error, :invalid_configuration}
  def configure(agent_server, options) when is_list(options) do
    with {:ok, options} <-
           Keyword.validate(options, [:system_prompt, :tools]),
         system_prompt when is_binary(system_prompt) <-
           Keyword.fetch!(options, :system_prompt),
         true <- String.trim(system_prompt) != "",
         tools when is_list(tools) <- Keyword.fetch!(options, :tools),
         :ok <- validate_tools(tools),
         {:ok, _agent} <- Jido.AI.set_system_prompt(agent_server, system_prompt),
         :ok <- register_tools(agent_server, tools) do
      :ok
    else
      _invalid -> {:error, :invalid_configuration}
    end
  rescue
    _exception -> {:error, :invalid_configuration}
  end

  def configure(_agent_server, _options), do: {:error, :invalid_configuration}

  defp validate_tools(tools) do
    names = Enum.map(tools, &tool_name/1)

    if Enum.all?(names, &is_binary/1) and length(names) == length(Enum.uniq(names)) do
      :ok
    else
      {:error, :invalid_configuration}
    end
  end

  defp tool_name(module) when is_atom(module) do
    with true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :definition, 0),
         true <- function_exported?(module, :execute, 2),
         true <- function_exported?(module, :name, 0),
         true <- function_exported?(module, :run, 2),
         %Definition{name: name} when is_binary(name) <- module.definition(),
         ^name <- module.name() do
      name
    else
      _invalid -> nil
    end
  end

  defp tool_name(_module), do: nil

  defp register_tools(agent_server, tools) do
    Enum.reduce_while(tools, :ok, fn tool, :ok ->
      case Jido.AI.register_tool(agent_server, tool) do
        {:ok, _agent} -> {:cont, :ok}
        {:error, _reason} -> {:halt, {:error, :invalid_configuration}}
      end
    end)
  end
end
