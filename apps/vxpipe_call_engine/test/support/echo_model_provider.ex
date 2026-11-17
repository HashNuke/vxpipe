defmodule Vxpipe.CallEngine.TestEchoModelProvider do
  @moduledoc "Credential-free model fixture for speech and transport contract tests."
  @behaviour Vxpipe.AgentRuntime.ModelProvider

  alias Vxpipe.AgentRuntime.{Message, ModelResponse}

  def new(options), do: {:ok, Map.new(options)}

  @impl true
  def readiness(_model), do: :ready

  @impl true
  def generate(model, request) do
    if observer = Map.get(model, :observer),
      do: send(observer, {:test_echo_model_request, request})

    %Message{content: content} = Enum.find(Enum.reverse(request.messages), &(&1.role == :user))
    ModelResponse.new(text: "Echo: " <> participant_text(content))
  end

  @impl true
  def stream(model, request, emit) do
    with {:ok, response} <- generate(model, request),
         :ok <- emit.(response.text),
         do: {:ok, response}
  end

  # Simulate a model reading the participant envelope. Only the outer message is
  # interpreted; JSON-shaped human speech in its message remains literal text.
  defp participant_text(content) do
    case JSON.decode(content) do
      {:ok, %{"type" => "participant_message", "message" => text}} when is_binary(text) -> text
      _legacy -> content
    end
  end
end
