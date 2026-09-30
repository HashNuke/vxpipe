defmodule Vxpipe.CallEngine.TestElevenLabsAgentLeaseAPI do
  @moduledoc false

  alias Vxpipe.Providers.ElevenLabs.AgentConnection

  def with_agent(client, _definition, consume) do
    send(client.observer, {:elevenlabs_agent_create, self()})

    receive do
      :agent_created ->
        {:ok, connection} =
          AgentConnection.new(
            "wss://api.elevenlabs.io/v1/convai/conversation?conversation_signature=synthetic-private-token"
          )

        result = consume.(connection)
        send(client.observer, {:elevenlabs_agent_delete, self()})

        receive do
          :agent_deleted -> {:ok, result}
          :agent_delete_failed -> {:error, :cleanup_failed}
        after
          2_000 -> {:error, :cleanup_failed}
        end

      :agent_create_failed ->
        {:error, :provider_unavailable}
    after
      2_000 -> {:error, :provider_unavailable}
    end
  end
end
