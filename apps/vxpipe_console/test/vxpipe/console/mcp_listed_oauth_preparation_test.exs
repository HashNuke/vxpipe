defmodule Vxpipe.Console.MCPListedOAuthPreparationTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.{IntegrationsDirectory.Listing, MCPOAuthPreparation}
  alias Vxpipe.Console.IntegrationsDirectory.Request
  @origin "https://console.example.test"
  @endpoint "https://calendar.example.test/mcp"
  @issuer "https://auth.example.test"
  @example Path.expand(
             "../../../../../docs/assets/integrations/integrations-directory.example.json",
             __DIR__
           )

  setup do
    tasks = start_supervised!({Task.Supervisor, []})

    runner =
      start_supervised!(
        {Vxpipe.MCP.PreflightRunner, name: nil, task_supervisor: tasks, interval: 0}
      )

    %{runner: runner}
  end

  test "OAuth target resolution does not discover or register and preparation reuses its snapshot",
       data do
    {reference, options} = configuration(data, "dcr")
    input = %{"listing" => reference, "revision" => "draft"}

    public_options =
      Keyword.put(options, :http_client, fn _, _, _ ->
        flunk("target resolution must not contact OAuth")
      end)

    assert {:ok, target} = MCPOAuthPreparation.resolve_target(public_options, "tenant", input)
    assert_receive :directory_lookup
    refute_received :registered
    assert target.revision == "draft"
    assert target.directory_entry["authentication"]["registration"] == "dcr"

    options =
      Keyword.put(options, :listing_options,
        fetcher: fn _, _ -> flunk("second directory lookup") end
      )

    assert {:ok, prepared} =
             MCPOAuthPreparation.prepare_target(options, "tenant", input, @origin, target)

    assert prepared.secrets["directory_entry"] == target.directory_entry
    assert prepared.attributes.resource == target.endpoint
    assert_receive :registered
  end

  test "invalid explicit issuer fails target resolution before reading the directory", data do
    {reference, options} = configuration(data, "dcr")
    input = %{"listing" => reference, "revision" => "draft", "issuer" => "http://invalid.test"}

    assert {:error, :invalid_oauth_issuer} =
             MCPOAuthPreparation.resolve_target(options, "tenant", input)

    refute_received :directory_lookup
    refute_received :registered
  end

  test "listed registration recipes own endpoints and carry accepted configuration privately",
       data do
    for {registration, expected} <- [
          {"discover", "cimd"},
          {"cimd", "cimd"},
          {"dcr", "dcr"},
          {"preregistered", "own_client"}
        ] do
      {reference, options} = configuration(data, registration)

      credentials =
        if registration == "preregistered",
          do: %{
            "client_id" => "registered-client",
            "client_auth_method" => "client_secret_basic",
            "client_secret" => "synthetic-secret"
          },
          else: %{}

      input = %{
        "listing" => reference,
        "revision" => "draft",
        "credentials" => credentials,
        "endpoint" => "https://attacker.example.test/mcp",
        "auth_method" => "none"
      }

      assert {:ok, prepared} = MCPOAuthPreparation.prepare(options, "tenant", input, @origin)
      assert prepared.attributes.resource == @endpoint
      assert prepared.attributes.draft_revision == "draft"
      assert prepared.secrets["registration_method"] == expected
      assert prepared.secrets["directory_entry"]["authentication"]["registration"] == registration
      assert prepared.secrets["directory_entry"]["endpoint"] == @endpoint
      assert prepared.secrets["directory_entry"]["name"] == "Example Calendar"
      assert prepared.secrets["scopes"] == ["tools.read"]
      refute inspect(prepared) =~ "synthetic-secret"
      query = URI.decode_query(URI.parse(prepared.authorization_url).query)
      assert query["resource"] == @endpoint
      assert query["scope"] == "tools.read"
      assert_receive :directory_lookup

      if registration == "dcr",
        do: assert_receive(:registered),
        else: refute_received(:registered)
    end
  end

  test "saved OAuth preparation uses accepted configuration during directory outage", data do
    {reference, options} = configuration(data, "cimd")
    assert {:ok, entry} = Listing.resolve(reference, options[:listing_options])
    assert_receive :directory_lookup

    options =
      Keyword.put(options, :listing_options,
        fetcher: fn _, _ -> flunk("saved configuration is local") end
      )

    input = %{
      "revision" => "saved-draft",
      "credentials" => %{},
      "endpoint" => "https://attacker.example.test/mcp",
      "auth_method" => "none"
    }

    assert {:ok, prepared} =
             MCPOAuthPreparation.prepare_saved(options, "tenant", input, @origin, %{}, entry)

    assert prepared.attributes.resource == @endpoint
    assert prepared.secrets["directory_entry"] == entry
    refute_received :directory_lookup
  end

  test "private overrides and changed references never reach registration", data do
    {reference, options} = configuration(data, "dcr")
    input = %{"listing" => reference, "revision" => "draft", "credentials" => %{}}

    assert {:error, :mcp_listing_unavailable} =
             MCPOAuthPreparation.prepare(
               options,
               "tenant",
               put_in(input, ["listing", "entry_revision"], 999),
               @origin
             )

    for extra <- [
          %{"directory_entry" => %{"endpoint" => @endpoint}},
          %{"credentials" => %{"token_endpoint" => "https://attacker.example.test/token"}},
          %{"credentials" => %{"headers" => [%{"name" => "X-Extra", "value" => "synthetic"}]}}
        ] do
      assert {:error, :invalid_oauth_preparation} =
               MCPOAuthPreparation.prepare(options, "tenant", Map.merge(input, extra), @origin)
    end

    refute_received :registered
  end

  test "unsupported live browser capabilities cannot be overridden by a directory hint", data do
    {reference, options} =
      configuration(data, "cimd", %{"code_challenge_methods_supported" => []})

    assert {:error, :unsupported_oauth_capabilities} =
             MCPOAuthPreparation.prepare(
               options,
               "tenant",
               %{"listing" => reference, "revision" => "draft", "credentials" => %{}},
               @origin
             )

    refute_received :registered
  end

  test "missing resource metadata preserves explicit-issuer Own client fallback", data do
    {reference, options} = configuration(data, "discover")
    original = options[:http_client]

    options =
      Keyword.put(options, :http_client, fn uri, headers, settings ->
        if uri.host == "calendar.example.test",
          do: {:ok, %{status: 404, headers: [], body: "{}"}},
          else: original.(uri, headers, settings)
      end)

    input = %{
      "listing" => reference,
      "revision" => "manual-issuer",
      "issuer" => @issuer,
      "credentials" => %{"client_id" => "registered-client", "client_auth_method" => "none"}
    }

    assert {:ok, prepared} = MCPOAuthPreparation.prepare(options, "tenant", input, @origin)
    assert prepared.secrets["registration_method"] == "own_client"
    entry = prepared.secrets["directory_entry"]

    assert {:ok, saved} =
             MCPOAuthPreparation.prepare_saved(
               options,
               "tenant",
               Map.delete(input, "listing"),
               @origin,
               %{},
               entry
             )

    assert saved.secrets["registration_method"] == "own_client"
    refute_received :registered
  end

  test "capability loss between selection and revalidation stops registration and handoff",
       data do
    for {registration, change, error} <- [
          {"cimd", %{"client_id_metadata_document_supported" => false},
           :oauth_registration_unavailable},
          {"dcr", %{"code_challenge_methods_supported" => []}, :unsupported_oauth_capabilities}
        ] do
      {reference, options} = configuration(data, registration)
      counter = start_supervised!({Agent, fn -> 0 end}, id: registration)
      original = options[:http_client]

      options =
        Keyword.put(options, :http_client, fn uri, headers, settings ->
          {:ok, response} = original.(uri, headers, settings)

          if uri.host == "auth.example.test" do
            count = Agent.get_and_update(counter, &{&1, &1 + 1})

            body =
              if count == 0,
                do: response.body,
                else: response.body |> JSON.decode!() |> Map.merge(change) |> JSON.encode!()

            {:ok, %{response | body: body}}
          else
            {:ok, response}
          end
        end)

      assert {:error, ^error} =
               MCPOAuthPreparation.prepare(
                 options,
                 "tenant",
                 %{"listing" => reference, "revision" => "draft"},
                 @origin
               )
    end

    refute_received :registered
  end

  defp configuration(data, registration, metadata_overrides \\ %{}) do
    recipe = %{"type" => "oauth2", "registration" => registration, "scopes" => ["calendar.write"]}

    page =
      @example
      |> File.read!()
      |> JSON.decode!()
      |> Map.put("installation_version", Request.installation_version())
      |> Map.update!("items", fn items ->
        Enum.map(items, &put_in(&1, ["connection", "authentication"], recipe))
      end)

    [item] = page["items"]
    reference = Listing.reference(page, item, %{"category" => "calendar", "limit" => 1})
    owner = self()

    metadata =
      Map.merge(
        %{
          "issuer" => @issuer,
          "authorization_endpoint" => @issuer <> "/authorize",
          "token_endpoint" => @issuer <> "/token",
          "registration_endpoint" => @issuer <> "/register",
          "client_id_metadata_document_supported" => true,
          "token_endpoint_auth_methods_supported" => ["none", "client_secret_basic"],
          "response_types_supported" => ["code"],
          "code_challenge_methods_supported" => ["S256"],
          "authorization_response_iss_parameter_supported" => true
        },
        metadata_overrides
      )

    options = [
      preflight_runner: data.runner,
      listing_options: [
        fetcher: fn :integrations, _ ->
          send(owner, :directory_lookup)
          {:ok, %{body: page}}
        end
      ],
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      http_client: fn uri, _, _ ->
        {status, body} =
          cond do
            uri.path == "/mcp" ->
              {401, %{}}

            uri.host == "calendar.example.test" ->
              {200,
               %{
                 "resource" => @endpoint,
                 "authorization_servers" => [@issuer],
                 "scopes_supported" => ["tools.read"]
               }}

            uri.host == "auth.example.test" ->
              {200, metadata}

            true ->
              flunk("untrusted endpoint reached")
          end

        {:ok, %{status: status, headers: [], body: JSON.encode!(body)}}
      end,
      request_fun: fn :post, {uri, _headers, _type, _body}, _, _ ->
        assert URI.parse(to_string(uri)).path == "/register"
        send(owner, :registered)

        {:ok,
         {{~c"HTTP/1.1", 201, ~c"Created"}, [],
          JSON.encode!(%{
            "client_id" => "registered",
            "token_endpoint_auth_method" => "none",
            "redirect_uris" => [@origin <> "/oauth/mcp/callback"]
          })}}
      end
    ]

    {reference, options}
  end
end
