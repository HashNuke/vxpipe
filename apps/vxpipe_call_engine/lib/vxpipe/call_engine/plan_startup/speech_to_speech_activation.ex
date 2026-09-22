defmodule Vxpipe.CallEngine.PlanStartup.SpeechToSpeechActivation do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.ToolDescriptors
  alias Vxpipe.CallEngine.PlanStartup.AgentActivation

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
         {:ok, descriptors} <- ToolDescriptors.compile(participant.tools, variables),
         true <- length(descriptors) <= 64 do
      tools = Enum.map(descriptors, &Map.take(&1, [:name, :description, :input_schema]))

      if :erlang.external_size({prompt, tools}) <= 131_072 do
        {:ok, %__MODULE__{system_prompt: prompt, tools: tools}}
      else
        {:error, :invalid_configuration}
      end
    else
      _invalid -> {:error, :invalid_configuration}
    end
  rescue
    _exception -> {:error, :invalid_configuration}
  end
end
