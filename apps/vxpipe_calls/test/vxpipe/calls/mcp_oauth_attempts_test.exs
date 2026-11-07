defmodule Vxpipe.Calls.MCPOAuthAttemptsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.MCPOAuthAttempts
  alias Vxpipe.Calls.Test.{MCPOAuthAttemptFixture, MCPRepositoryFixture}
  alias Vxpipe.Identity.Principal
  @tenant "AAAAAAAAAAAAAAAA"

  setup do
    principal = %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(~w(tenant_services.read tenant_services.write)),
      assigned_tenants: %{@tenant => :read_write}
    }

    options = [
      credential_repository: {MCPRepositoryFixture, self()},
      mcp_oauth_attempt_repository: {MCPOAuthAttemptFixture, self()},
      refresh_authority: fn -> {:ok, principal} end
    ]

    %{principal: principal, options: options}
  end

  test "start persists prepared secrets before handing off only authorization URL", data do
    prepared = %Vxpipe.Calls.PreparedMCPOAuth{
      authorization_url: "https://auth.test/authorize?state=opaque",
      attributes: %{
        state: String.duplicate("s", 43),
        issuer: "https://auth.test",
        redirect_uri: "https://console.test/oauth/mcp/callback",
        resource: "https://mcp.test/mcp",
        draft_revision: "draft"
      },
      secrets: %{"code_verifier" => "private"}
    }

    options =
      start_options(data, {:ok, prepared})
      |> Keyword.put(:oauth_return_to, "/t/AAAAAAAAAAAAAAAA/services/ai?q=calendar")

    assert {:ok, result} = MCPOAuthAttempts.start(data.principal, @tenant, %{}, options)
    assert result.authorization_url == prepared.authorization_url
    assert result.attempt_id == "attempt"
    refute Map.has_key?(result, :secrets)
    assert_receive {:oauth_prepare, %{}, "https://console.test"}
    assert_receive {:attempt_issue, @tenant, attributes, %{"code_verifier" => "private"}}
    assert attributes.installation_revision == 2
    assert attributes.return_to == "/t/AAAAAAAAAAAAAAAA/services/ai?q=calendar"
    assert attributes.generation == 1
    assert attributes.connection_id == result.connection_id
  end

  test "installation changes during preparation prevent persistence and handoff", data do
    counter = start_supervised!({Agent, fn -> 1 end})

    prepared = %Vxpipe.Calls.PreparedMCPOAuth{
      authorization_url: "https://auth.test/authorize",
      attributes: %{},
      secrets: %{}
    }

    options =
      start_options(data, {:ok, prepared})
      |> Keyword.put(:installation_identity, fn ->
        revision = Agent.get_and_update(counter, fn value -> {value, value + 1} end)
        {:ok, %{origin: "https://console.test", revision: revision}}
      end)

    assert {:error, :mcp_installation_changed} =
             MCPOAuthAttempts.start(data.principal, @tenant, %{}, options)

    refute_received {:attempt_issue, _, _, _}
  end

  test "listed preparation is bound to the proposed entry and draft before persistence", data do
    entry = %{
      "directory_id" => "directory",
      "integration_id" => "calendar",
      "revision" => 1,
      "name" => "Calendar",
      "endpoint" => "https://mcp.test/mcp",
      "authentication" => %{"type" => "oauth2", "registration" => "cimd"}
    }

    reference = %{
      "directory_id" => "directory",
      "integration_id" => "calendar",
      "entry_revision" => 1,
      "page" => %{}
    }

    input = %{"listing" => reference, "revision" => "draft"}

    prepared = %Vxpipe.Calls.PreparedMCPOAuth{
      authorization_url: "https://auth.test/authorize",
      attributes: %{resource: entry["endpoint"], draft_revision: "draft"},
      secrets: %{"directory_entry" => entry}
    }

    for mismatch <- [
          %{prepared | attributes: %{resource: entry["endpoint"], draft_revision: "other"}},
          %{
            prepared
            | attributes: %{resource: "https://other.test/mcp", draft_revision: "draft"}
          },
          %{prepared | secrets: %{}},
          %{prepared | secrets: %{"directory_entry" => Map.put(entry, "revision", 2)}},
          %{prepared | secrets: %{"directory_entry" => Map.put(entry, "integration_id", "other")}}
        ] do
      assert {:error, :oauth_preparation_failed} =
               MCPOAuthAttempts.start(
                 data.principal,
                 @tenant,
                 input,
                 start_options(data, {:ok, mismatch})
               )
    end

    refute_received {:attempt_issue, _, _, _}

    assert {:ok, _} =
             MCPOAuthAttempts.start(
               data.principal,
               @tenant,
               input,
               start_options(data, {:ok, prepared})
             )

    assert_receive {:attempt_issue, @tenant, _, %{"directory_entry" => ^entry}}
  end

  test "malformed listed proposals stop before preparation", data do
    for input <- [
          %{"listing" => "bad", "revision" => "draft"},
          %{"listing" => %{}, "revision" => "draft", "directory_entry" => %{}},
          %{"listing" => %{"unexpected" => String.duplicate("x", 8192)}, "revision" => "draft"}
        ] do
      assert {:error, :invalid_oauth_preparation} =
               MCPOAuthAttempts.start(
                 data.principal,
                 @tenant,
                 input,
                 start_options(data, {:error, :unused})
               )
    end

    refute_received {:oauth_prepare, _, _}
  end

  test "start denies before remote work and rejects missing installation identity", data do
    options = start_options(data, {:error, :unused})
    reader = %{data.principal | grants: MapSet.new()}
    assert {:error, :forbidden} = MCPOAuthAttempts.start(reader, @tenant, %{}, options)
    options = Keyword.put(options, :installation_identity, fn -> {:error, :unavailable} end)

    assert {:error, :mcp_installation_unavailable} =
             MCPOAuthAttempts.start(data.principal, @tenant, %{}, options)

    refute_received {:oauth_prepare, _, _}
    refute_received {:attempt_issue, _, _, _}
  end

  test "preparation failures do not leak provider details or persist state", data do
    options = start_options(data, {:error, {:provider, "private"}})

    assert {:error, :oauth_preparation_failed} =
             MCPOAuthAttempts.start(data.principal, @tenant, %{}, options)

    refute_received {:attempt_issue, _, _, _}
  end

  defp start_options(data, result) do
    data.options ++
      [
        mcp_oauth_preparation: {Vxpipe.Calls.Test.MCPOAuthPreparationFixture, {self(), result}},
        installation_identity: fn -> {:ok, %{origin: "https://console.test", revision: 2}} end
      ]
  end

  test "callback locates tenant using session identity then authorizes and claims", data do
    options =
      Keyword.put(data.options, :installation_identity, fn ->
        {:ok,
         %{
           origin: "https://console.test",
           revision: 2,
           redirect_uri: "https://console.test/oauth/mcp/callback"
         }}
      end)

    assert {:ok, @tenant, %Vxpipe.Calls.ResolvedMCPOAuthAttempt{}} =
             MCPOAuthAttempts.claim_callback(data.principal, "state", options)

    assert_receive {:attempt_locate, "state", %{user_id: "user", session_id: "session"}}

    assert_receive {:attempt_claim, @tenant, "state",
                    %{
                      user_id: "user",
                      session_id: "session",
                      installation_revision: 2,
                      redirect_uri: "https://console.test/oauth/mcp/callback"
                    }}
  end

  test "callback cannot consume another tenant's state without current permission", data do
    reader = %{data.principal | assigned_tenants: %{@tenant => :read}}
    assert {:error, :forbidden} = MCPOAuthAttempts.claim_callback(reader, "state", data.options)
    refute_received {:attempt_claim, _, _, _}

    assert {:error, :forbidden} =
             MCPOAuthAttempts.claim_callback(
               %{data.principal | credential_kind: :api_key},
               "state",
               data.options
             )
  end

  test "completion checks protocol then persists only under current authority", data do
    options = completion_options(data)

    assert {:ok, @tenant, record} =
             MCPOAuthAttempts.complete(data.principal, "state", :callback, options)

    assert record.id == "connection"
    refute Map.has_key?(record, :secrets)
    assert_receive {:attempt_claim, @tenant, "state", _}
    assert_receive {:attempt_completed, @tenant}
    assert_receive {:oauth_saved, @tenant, "connection", %{"access_token" => "private"}}
  end

  test "permission loss during completion never persists tokens", data do
    count = start_supervised!({Agent, fn -> 0 end})

    options =
      completion_options(data)
      |> Keyword.put(:refresh_authority, fn ->
        call = Agent.get_and_update(count, &{&1, &1 + 1})
        {:ok, if(call == 0, do: data.principal, else: %{data.principal | grants: MapSet.new()})}
      end)

    assert {:error, :forbidden} =
             MCPOAuthAttempts.complete(data.principal, "state", :callback, options)

    assert_receive {:attempt_completed, @tenant}
    refute_received {:oauth_saved, _, _, _}
  end

  defp completion_options(data) do
    data.options ++
      [
        mcp_oauth_completion: {MCPOAuthAttemptFixture, self()},
        mcp_connection_repository: {MCPOAuthAttemptFixture, self()},
        installation_identity: fn ->
          {:ok,
           %{
             origin: "https://console.test",
             revision: 2,
             redirect_uri: "https://console.test/oauth/mcp/callback"
           }}
        end
      ]
  end

  test "issue binds trusted principal identity instead of supplied identity", data do
    assert {:ok, _} =
             MCPOAuthAttempts.issue(
               data.principal,
               @tenant,
               %{user_id: "forged", session_id: "forged"},
               %{"verifier" => "private"},
               data.options
             )

    assert_receive {:attempt_issue, @tenant, attributes, %{"verifier" => "private"}}
    assert attributes.user_id == "user"
    assert attributes.session_id == "session"
  end

  test "claim uses current principal and installation identity", data do
    installation = %{
      installation_revision: 2,
      redirect_uri: "https://console.test/oauth/mcp/callback"
    }

    assert {:ok, _} =
             MCPOAuthAttempts.claim(data.principal, @tenant, "state", installation, data.options)

    assert_receive {:attempt_claim, @tenant, "state", authority}
    assert authority == Map.merge(installation, %{user_id: "user", session_id: "session"})
  end

  test "revoked permission, changed session and non-browser credentials cannot touch attempts",
       data do
    for current <- [
          %{data.principal | grants: MapSet.new()},
          %{data.principal | session_public_id: "other"}
        ] do
      options = Keyword.put(data.options, :refresh_authority, fn -> {:ok, current} end)

      assert {:error, :forbidden} =
               MCPOAuthAttempts.issue(data.principal, @tenant, %{}, %{}, options)

      assert {:error, :forbidden} =
               MCPOAuthAttempts.claim(data.principal, @tenant, "state", %{}, options)
    end

    assert {:error, :forbidden} =
             MCPOAuthAttempts.issue(
               %{data.principal | credential_kind: :api_key},
               @tenant,
               %{},
               %{},
               data.options
             )

    refute_received {:attempt_issue, _, _, _}
    refute_received {:attempt_claim, _, _, _}
  end
end
