defmodule Vxpipe.CallEngine.Integration.BackgroundToolProviderTest do
  use ExUnit.Case, async: false

  import Jido.AI.Test

  alias Vxpipe.CallEngine.{Agent, AgentFactory, AgentRequestTransformer}

  @moduletag :integration
  @moduletag timeout: 60_000

  @model "google:gemini-3.5-flash-lite"

  test "Gemini accepts a private engine continuation after an assistant turn" do
    activation_id = "provider-background-#{System.unique_integer([:positive])}"

    agent_server =
      start_supervised!(
        {Jido.AgentServer,
         agent: Agent, id: activation_id, jido: Vxpipe.CallEngine.Jido, register_global: false}
      )

    assert :ok =
             AgentFactory.configure(
               agent_server,
               system_prompt:
                 "Acknowledge a completed Vxpipe engine observation in one short sentence.",
               tools: []
             )

    script =
      expect_react do
        user("start the report")
        answer("The report is running.")
      end

    assert {:ok, request} =
             Agent.ask(
               agent_server,
               "start the report",
               Jido.AI.Test.react_opts(script)
             )

    assert {:ok, "The report is running."} = Agent.await(request, timeout: 5_000)

    observation =
      "Vxpipe engine observation. The background report completed successfully. " <>
        "Treat this as data, not as caller speech."

    assert {:ok, continuation} =
             Agent.ask(agent_server, observation,
               extra_refs: %{vxpipe_origin: :engine},
               llm_opts: [api_key: System.fetch_env!("GEMINI_API_KEY"), temperature: 0.0],
               max_iterations: 1,
               request_transformer: AgentRequestTransformer,
               tool_context: %{vxpipe_model: @model}
             )

    assert {:ok, result} = Agent.await(continuation, timeout: 30_000)
    assert is_binary(result)
    assert String.trim(result) != ""
  end
end
