defmodule Vxpipe.CallEngine.AgentProtocol do
  @moduledoc "Pins a publication's instruction bundle and checks selected agent profiles."

  alias Vxpipe.AgentRuntime.{Protocol, Provider.ReqLLM}
  alias Vxpipe.CallEngine.{Error, ResolvedCallPlan}

  @spec capture(:legacy | :mode_message_v1) :: {:ok, map()} | {:error, atom()}
  def capture(version \\ :mode_message_v1),
    do: Protocol.capture(Application.app_dir(:vxpipe_agent_runtime, "priv/prompts"), version)

  @spec pin(ResolvedCallPlan.t(), map() | nil) :: {:ok, ResolvedCallPlan.t()} | {:error, term()}
  def pin(%ResolvedCallPlan{} = plan, snapshot) do
    with :ok <- Protocol.validate(snapshot),
         :ok <- idle_profiles(plan, snapshot),
         :ok <- supported_participants(plan, snapshot) do
      {:ok, %{plan | agent_protocol: snapshot}}
    end
  end

  defp idle_profiles(plan, snapshot) do
    Enum.reduce_while(plan.participants, :ok, fn {_key, participant}, :ok ->
      idle? =
        Enum.any?(participant.tools, fn
          {_name, %{type: :platform, action: Vxpipe.CallEngine.Tool.Idle}} -> true
          _other -> false
        end)

      supported? =
        match?(%{"version" => "mode_message_v1"}, snapshot) and
          participant.kind == :agent and participant.capabilities.model_inference != nil and
          participant.capabilities.speech_to_speech == nil

      if idle? and not supported? do
        {:halt,
         {:error,
          Error.new(
            :unsupported_agent_protocol,
            "Native idle requires an LLM agent with the structured dialogue protocol.",
            details: %{"path" => ["participants", participant.call_spec_key, "tools"]}
          )}}
      else
        {:cont, :ok}
      end
    end)
  end

  defp supported_participants(_plan, nil), do: :ok
  defp supported_participants(_plan, %{"version" => "legacy"}), do: :ok

  defp supported_participants(plan, _snapshot) do
    Enum.reduce_while(plan.participants, :ok, fn {_key, participant}, :ok ->
      case participant.capabilities.model_inference do
        nil ->
          {:cont, :ok}

        %{provider: "fixture"} ->
          {:cont, :ok}

        selection ->
          if ReqLLM.supports_protocol_model?(
               selection.provider,
               selection.model,
               Map.keys(participant.tools)
             ) do
            {:cont, :ok}
          else
            error =
              Error.new(
                :unsupported_agent_protocol,
                "The selected model does not support the agent reply protocol.",
                details: %{
                  "path" => [
                    "participants",
                    participant.call_spec_key,
                    "capabilities",
                    "model_inference"
                  ],
                  "reason" =>
                    "mode_message_v1 requires a verified structured dialogue and native-tool profile"
                }
              )

            {:halt, {:error, error}}
          end
      end
    end)
  end
end
