defmodule Vxpipe.CallEngine.PlanStartup.SpeechToSpeechActivation do
  @moduledoc false

  alias Vxpipe.AgentRuntime.ToolRegistry
  alias Vxpipe.CallEngine.AgentRuntime.ToolDescriptors
  alias Vxpipe.CallEngine.PlanStartup.AgentActivation
  alias Vxpipe.CallEngine.RemoteMCP.Activation, as: RemoteActivation

  @derive {Inspect, only: []}
  @enforce_keys [:system_prompt, :tools]
  defstruct @enforce_keys

  def resolve(plan, participant, options) do
    with prompt when is_binary(prompt) <- participant.prompt,
         true <- byte_size(prompt) <= 65_536 and String.valid?(prompt),
         true <- map_size(participant.tools) <= 64,
         {:ok, variables} <-
           AgentActivation.variable_binding(
             plan,
             participant,
             Keyword.delete(options, :validation_only)
           ),
         {:ok, tools, registry} <- prepare_tools(participant.tools, variables) do
      if length(tools) <= 64 and :erlang.external_size({prompt, tools}) <= 131_072 do
        {:ok, %__MODULE__{system_prompt: prompt, tools: tools}, registry}
      else
        {:error, :invalid_configuration}
      end
    else
      _invalid -> {:error, :invalid_configuration}
    end
  rescue
    _exception -> {:error, :invalid_configuration}
  end

  def registry(plan, participant, options, remote_owner) when is_pid(remote_owner) do
    with {:ok, variables} <- AgentActivation.variable_binding(plan, participant, options),
         {:ok, descriptors} <- ToolDescriptors.compile(participant.tools, variables, remote_owner),
         do: ToolRegistry.new(descriptors)
  end

  defp prepare_tools(bindings, variables) do
    if RemoteActivation.selected?(bindings) do
      with {:ok, tools} <- ToolDescriptors.project(bindings, variables), do: {:ok, tools, nil}
    else
      with {:ok, descriptors} <- ToolDescriptors.compile(bindings, variables),
           {:ok, registry} <- ToolRegistry.new(descriptors) do
        {:ok, Enum.map(descriptors, &Map.take(&1, [:name, :description, :input_schema])),
         registry}
      end
    end
  end
end
