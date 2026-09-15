defmodule Vxpipe.CallEngine.TestEchoModelProvider do
  @moduledoc "Credential-free model fixture for speech and transport contract tests."
  @behaviour Vxpipe.AgentRuntime.ModelProvider

  alias Vxpipe.AgentRuntime.{Message, ModelResponse}

  def new(options), do: {:ok, Map.new(options)}

  @impl true
  def readiness(_model), do: :ready

  @impl true
  def generate(_model, request) do
    %Message{content: content} = Enum.find(Enum.reverse(request.messages), &(&1.role == :user))
    ModelResponse.new(text: "Echo: " <> content)
  end

  @impl true
  def stream(model, request, emit) do
    with {:ok, response} <- generate(model, request),
         :ok <- emit.(response.text),
         do: {:ok, response}
  end
end
