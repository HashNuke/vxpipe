defmodule Vxpipe.Providers.ElevenLabs.AgentAPITest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.ElevenLabs.AgentAPI

  test "reads available model identifiers without exposing unrelated catalog fields" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/convai/llm/list"

      Req.Test.json(conn, %{
        "llms" => [
          %{"llm" => "gemini-3.5-flash-lite", "private" => "synthetic-private-detail"}
        ]
      })
    end)

    assert {:ok, ["gemini-3.5-flash-lite"]} = AgentAPI.available_models(client())
  end

  test "creates, signs and deletes only the agent it owns, hiding credentials and signed URLs" do
    observer = self()

    signed =
      "wss://api.elevenlabs.io/v1/convai/conversation?agent_id=agent_synthetic&conversation_signature=synthetic-private-token"

    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "xi-api-key") == ["synthetic-private-key"]
      send(observer, {:agent_api_request, conn.method, conn.request_path})

      case {conn.method, conn.request_path} do
        {"POST", "/v1/convai/agents/create"} ->
          Req.Test.json(conn, %{"agent_id" => "agent_synthetic"})

        {"GET", "/v1/convai/conversation/get-signed-url"} ->
          Req.Test.json(conn, %{"signed_url" => signed})

        {"DELETE", "/v1/convai/agents/agent_synthetic"} ->
          Plug.Conn.send_resp(conn, 204, "")
      end
    end)

    client = client()
    refute inspect(client) =~ "synthetic-private-key"

    assert {:ok, :observed} =
             AgentAPI.with_agent(client, %{"conversation_config" => %{}}, fn connection ->
               assert connection.url == signed
               assert connection.headers == []
               refute inspect(connection) =~ "synthetic-private-token"
               :observed
             end)

    assert_received {:agent_api_request, "POST", "/v1/convai/agents/create"}
    assert_received {:agent_api_request, "GET", "/v1/convai/conversation/get-signed-url"}
    assert_received {:agent_api_request, "DELETE", "/v1/convai/agents/agent_synthetic"}
  end

  test "deletes its created agent after signing failure without exposing private details" do
    observer = self()

    Req.Test.stub(__MODULE__, fn conn ->
      case conn.method do
        "POST" ->
          Req.Test.json(conn, %{"agent_id" => "agent_synthetic"})

        "GET" ->
          Plug.Conn.send_resp(conn, 403, "synthetic-private-provider-error")

        "DELETE" ->
          send(observer, :deleted_agent)
          Plug.Conn.send_resp(conn, 204, "")
      end
    end)

    assert {:error, {:provider_rejected, :sign, 403}} =
             AgentAPI.with_agent(client(), %{}, fn _ -> flunk("not signed") end)

    assert_received :deleted_agent
  end

  test "deletes after consumer failure and rejects foreign signed destinations" do
    observer = self()

    for signed <- [
          "wss://api.elevenlabs.io/v1/convai/conversation?conversation_signature=synthetic",
          "wss://foreign.example.com/v1/convai/conversation?conversation_signature=synthetic"
        ] do
      Req.Test.stub(__MODULE__, fn conn ->
        case conn.method do
          "POST" ->
            Req.Test.json(conn, %{"agent_id" => "agent_synthetic"})

          "GET" ->
            Req.Test.json(conn, %{"signed_url" => signed})

          "DELETE" ->
            send(observer, :deleted_agent)
            Plug.Conn.send_resp(conn, 204, "")
        end
      end)

      expected =
        if String.contains?(signed, "foreign"), do: :provider_unavailable, else: :consumer_failed

      assert {:error, ^expected} =
               AgentAPI.with_agent(client(), %{}, fn _ -> raise "synthetic-private-error" end)

      assert_received :deleted_agent
    end
  end

  test "cleanup failure cannot be reported as a successful lifecycle" do
    Req.Test.stub(__MODULE__, fn conn ->
      case conn.method do
        "POST" ->
          Req.Test.json(conn, %{"agent_id" => "agent_synthetic"})

        "GET" ->
          Req.Test.json(conn, %{
            "signed_url" =>
              "wss://api.elevenlabs.io/v1/convai/conversation?conversation_signature=synthetic"
          })

        "DELETE" ->
          Plug.Conn.send_resp(conn, 503, "synthetic-private-error")
      end
    end)

    assert {:error, :cleanup_failed} = AgentAPI.with_agent(client(), %{}, fn _ -> :observed end)
  end

  test "creation validation errors expose only fixed field names, never messages or values" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(422)
      |> Req.Test.json(%{"detail" => "retention_days rejected: synthetic-private-value"})
    end)

    assert {:error, {:provider_rejected, :create, 422, ["retention_days"]}} =
             AgentAPI.with_agent(client(), %{}, fn _ -> :unused end)
  end

  test "semantic creation rejection returns fixed diagnostic hints without provider text" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{"detail" => "thinking_budget rejected: synthetic-private-value"})
    end)

    assert {:error, {:provider_rejected, :create, 400, ["thinking_budget"]}} =
             AgentAPI.with_agent(client(), %{}, fn _ -> :unused end)
  end

  test "unstructured creation rejection returns only fixed lowercase hints" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{"detail" => "Daily limit is invalid: synthetic-private-value"})
    end)

    assert {:error, {:provider_rejected, :create, 400, ["limit", "invalid", "daily"]}} =
             AgentAPI.with_agent(client(), %{}, fn _ -> :unused end)
  end

  test "rejects unsafe agent paths before signing or deletion" do
    Req.Test.stub(__MODULE__, fn conn ->
      send(self(), {:request_method, conn.method})
      Req.Test.json(conn, %{"agent_id" => "../foreign"})
    end)

    assert {:error, :provider_unavailable} =
             AgentAPI.with_agent(client(), %{}, fn _ -> :unused end)

    assert_received {:request_method, "POST"}
    refute_received {:request_method, "DELETE"}
    assert {:error, :invalid_configuration} = AgentAPI.new("bad key")
  end

  defp client do
    assert {:ok, client} = AgentAPI.new("synthetic-private-key")
    %{client | request: Req.merge(client.request, plug: {Req.Test, __MODULE__})}
  end
end
