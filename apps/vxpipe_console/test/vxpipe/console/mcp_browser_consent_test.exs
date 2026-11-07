defmodule Vxpipe.Console.MCPBrowserConsentTest do
  use ExUnit.Case, async: true
  import Plug.Test
  alias Vxpipe.Console.Test.{MCPBrowserConsent, OutboundMCPOAuthServer}

  setup do
    peer = start_supervised!({Agent, fn -> OutboundMCPOAuthServer.initial("dcr") end})

    OutboundMCPOAuthServer.configure(peer, %{
      clients: %{"browser-client" => %{"token_endpoint_auth_method" => "none"}}
    })

    options = MCPBrowserConsent.init(%{state: peer})

    params = %{
      "client_id" => "browser-client",
      "redirect_uri" => OutboundMCPOAuthServer.origin() <> "/oauth/mcp/callback",
      "resource" => OutboundMCPOAuthServer.resource(),
      "response_type" => "code",
      "code_challenge_method" => "S256",
      "code_challenge" => "fixture-challenge",
      "scope" => "tools:read",
      "state" => "fixture-state"
    }

    %{peer: peer, options: options, params: params}
  end

  for decision <- ["allow", "deny"] do
    test "browser #{decision} is explicit and one-use", data do
      page = consent_page(data)
      assert page.status == 200
      assert page.resp_body =~ "Allow access"
      assert page.resp_body =~ "Deny access"
      assert Agent.get(data.peer, & &1.codes) == %{}
      assert OutboundMCPOAuthServer.count(data.peer, {"GET", "/authorize"}) == 0
      [_, request] = Regex.run(~r/name="request" value="([^"]+)"/, page.resp_body)
      response = decide(data, request, unquote(decision))
      assert response.status == 303
      [location] = Plug.Conn.get_resp_header(response, "location")
      callback = URI.decode_query(URI.parse(location).query)
      assert callback["state"] == "fixture-state"

      if unquote(decision) == "allow" do
        assert is_binary(callback["code"])
        refute callback["error"]
      else
        assert callback["error"] == "access_denied"
        refute callback["code"]
        assert Agent.get(data.peer, & &1.codes) == %{}
      end

      assert decide(data, request, "allow").status == 410
      assert OutboundMCPOAuthServer.count(data.peer, {"GET", "/authorize"}) == 1
    end
  end

  for valid <- [true, false] do
    test "CIMD consent fetches and checks the actual document (valid=#{valid})", data do
      OutboundMCPOAuthServer.configure(data.peer, %{mode: "cimd"})
      client = OutboundMCPOAuthServer.origin() <> "/oauth/client-metadata.json"
      owner = self()
      callback = data.params["redirect_uri"]

      fetch = fn url ->
        send(owner, {:metadata_fetch, url})

        {:ok,
         %{"client_id" => url, "redirect_uris" => if(unquote(valid), do: [callback], else: [])}}
      end

      data = %{
        data
        | options: Map.put(data.options, :metadata_fetch, fetch),
          params: Map.put(data.params, "client_id", client)
      }

      page = consent_page(data)
      refute_received {:metadata_fetch, _}
      [_, request] = Regex.run(~r/name="request" value="([^"]+)"/, page.resp_body)
      response = decide(data, request, "allow")
      assert_received {:metadata_fetch, ^client}
      assert response.status == if(unquote(valid), do: 303, else: 400)
      if not unquote(valid), do: assert(Agent.get(data.peer, & &1.codes) == %{})
    end
  end

  defp consent_page(data),
    do:
      conn(:get, "/authorize?" <> URI.encode_query(data.params))
      |> MCPBrowserConsent.call(data.options)

  defp decide(data, request, decision),
    do:
      conn(:post, "/consent", URI.encode_query(%{"request" => request, "decision" => decision}))
      |> MCPBrowserConsent.call(data.options)
end
