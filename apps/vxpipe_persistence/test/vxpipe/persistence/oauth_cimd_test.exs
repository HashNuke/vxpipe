defmodule Vxpipe.Persistence.OAuthCIMDTest do
  use Vxpipe.Persistence.DataCase, async: false
  alias Vxpipe.Persistence.OAuth.{Browser, Client, Store, Transaction}
  alias Vxpipe.Persistence.OAuthFixtures

  @client "https://client.example/oauth/client.json"

  setup do
    old = Application.get_env(:vxpipe_persistence, :oauth_client_metadata)
    owner = self()

    document = %{
      "client_id" => @client,
      "client_name" => "CIMD client",
      "application_type" => "native",
      "redirect_uris" => ["http://127.0.0.1/callback", "http://localhost/callback"],
      "logo_uri" => "https://client.example/logo.png",
      "token_endpoint_auth_method" => "none"
    }

    configure(document, owner)

    on_exit(fn ->
      if old,
        do: Application.put_env(:vxpipe_persistence, :oauth_client_metadata, old),
        else: Application.delete_env(:vxpipe_persistence, :oauth_client_metadata)
    end)

    Map.merge(OAuthFixtures.browser_user(), %{binding: Transaction.random(), document: document})
  end

  test "CIMD uses browser consent, exact code redirect, refresh and revocation", ctx do
    assert {:ok, request} = begin(ctx)
    assert_receive {:metadata_fetch, @client}
    assert {:ok, consent} = Browser.consent(request, ctx.binding, ctx.principal)
    assert consent.client_name == "CIMD client"
    assert consent.client_id == @client

    assert {:ok, issued} =
             Browser.complete_authorization(request, ctx.binding, ctx.principal, :approve)

    exchange = OAuthFixtures.exchange(@client, issued.code)

    assert {:error, :invalid_grant} =
             Store.exchange(
               Map.put(exchange, "redirect_uri", "http://127.0.0.1:43211/callback"),
               OAuthFixtures.resource()
             )

    assert {:ok, tokens} = Store.exchange(exchange, OAuthFixtures.resource())
    assert {:ok, _} = Store.authenticate(tokens.access_token, OAuthFixtures.resource())

    assert {:ok, rotated} =
             Store.exchange(
               OAuthFixtures.refresh(@client, tokens.refresh_token),
               OAuthFixtures.resource()
             )

    assert :ok =
             Store.revoke(
               %{"client_id" => @client, "token" => rotated.access_token},
               OAuthFixtures.resource()
             )

    assert {:error, :invalid_token} =
             Store.authenticate(rotated.access_token, OAuthFixtures.resource())

    assert {:ok, _} = begin(ctx)
    refute_received {:metadata_fetch, _}
    assert Repo.aggregate(Client, :count) == 1
  end

  test "invalid documents and private targets cannot create a client", ctx do
    configure(Map.put(ctx.document, "client_id", @client <> "?other"), self())
    assert {:error, :invalid_client} = begin(ctx)
    assert Repo.aggregate(Client, :count) == 0
    configure(ctx.document, self(), {127, 0, 0, 1})
    assert {:error, :invalid_client} = begin(ctx)
    assert Repo.aggregate(Client, :count) == 0
  end

  test "expired metadata is fetched again and a changed redirect cannot be approved", ctx do
    assert {:ok, request} = begin(ctx)
    assert {:ok, _} = Browser.consent(request, ctx.binding, ctx.principal)
    client = Repo.one!(Client)

    client
    |> Ecto.Changeset.change(metadata_expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    configure(Map.put(ctx.document, "redirect_uris", ["https://client.example/new"]), self())
    assert {:error, :invalid_request} = begin(ctx)

    assert {:error, :invalid_request} =
             Browser.complete_authorization(request, ctx.binding, ctx.principal, :approve)
  end

  test "the internal row ID cannot impersonate a CIMD client", ctx do
    assert {:ok, request} = begin(ctx)
    assert {:ok, _} = Browser.consent(request, ctx.binding, ctx.principal)

    assert {:ok, issued} =
             Browser.complete_authorization(request, ctx.binding, ctx.principal, :approve)

    client = Repo.one!(Client)

    assert {:error, :invalid_grant} =
             Store.exchange(
               OAuthFixtures.exchange(client.public_id, issued.code),
               OAuthFixtures.resource()
             )

    assert {:ok, _} =
             Store.exchange(
               OAuthFixtures.exchange(@client, issued.code),
               OAuthFixtures.resource()
             )
  end

  test "redirects and oversized metadata do not become trusted client records", ctx do
    for response <- [
          %{status: 302, headers: [{"location", @client <> "/next"}], body: ""},
          %{
            status: 200,
            headers: [{"content-type", "application/json"}],
            body: String.duplicate("x", 65_537)
          }
        ] do
      options = Application.fetch_env!(:vxpipe_persistence, :oauth_client_metadata)
      owner = self()

      Application.put_env(
        :vxpipe_persistence,
        :oauth_client_metadata,
        Keyword.put(options, :http_client, fn uri, _, _ ->
          send(owner, {:attempted, URI.to_string(uri)})
          {:ok, response}
        end)
      )

      assert {:error, :invalid_client} = begin(ctx)
      assert_receive {:attempted, @client}
      refute_received {:attempted, _}
      assert Repo.aggregate(Client, :count) == 0
    end
  end

  test "cache policy is bounded and no-store forces a new authorization fetch", ctx do
    options = Application.fetch_env!(:vxpipe_persistence, :oauth_client_metadata)

    Application.put_env(
      :vxpipe_persistence,
      :oauth_client_metadata,
      Keyword.put(options, :max_cache_seconds, 60)
    )

    assert {:ok, _} = begin(ctx)
    client = Repo.one!(Client)
    assert DateTime.diff(client.metadata_expires_at, DateTime.utc_now()) in 0..60

    client
    |> Ecto.Changeset.change(metadata_expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    owner = self()

    Application.put_env(
      :vxpipe_persistence,
      :oauth_client_metadata,
      Keyword.put(options, :http_client, fn _, _, _ ->
        send(owner, :no_store_fetch)

        {:ok,
         %{
           status: 200,
           headers: [{"content-type", "application/json"}, {"cache-control", "no-store"}],
           body: JSON.encode!(ctx.document)
         }}
      end)
    )

    assert {:ok, _} = begin(ctx)
    assert_receive :no_store_fetch
    assert {:ok, _} = begin(ctx)
    assert_receive :no_store_fetch
  end

  test "a slow fetch cannot overwrite a newer metadata refresh", ctx do
    assert {:ok, _} = begin(ctx)
    client = Repo.one!(Client)

    stale =
      client
      |> Ecto.Changeset.change(metadata_expires_at: DateTime.add(DateTime.utc_now(), -1))
      |> Repo.update!()

    options = Application.fetch_env!(:vxpipe_persistence, :oauth_client_metadata)

    Application.put_env(
      :vxpipe_persistence,
      :oauth_client_metadata,
      Keyword.put(options, :http_client, fn _, _, _ ->
        stale
        |> Ecto.Changeset.change(
          metadata: Map.put(stale.metadata, "client_name", "Newer client"),
          metadata_expires_at: DateTime.add(DateTime.utc_now(), 300)
        )
        |> Repo.update!()

        {:ok,
         %{
           status: 200,
           headers: [{"content-type", "application/json"}],
           body: JSON.encode!(ctx.document)
         }}
      end)
    )

    assert {:ok, request} = begin(ctx)
    assert {:ok, consent} = Browser.consent(request, ctx.binding, ctx.principal)
    assert consent.client_name == "Newer client"
  end

  defp begin(ctx),
    do:
      Browser.begin_authorization(
        OAuthFixtures.authorization(@client),
        OAuthFixtures.resource(),
        ctx.binding
      )

  defp configure(document, owner, address \\ {93, 184, 216, 34}) do
    Application.put_env(:vxpipe_persistence, :oauth_client_metadata,
      dns_resolver: fn _, _ -> {:ok, [address]} end,
      http_client: fn uri, _, _ ->
        send(owner, {:metadata_fetch, URI.to_string(uri)})

        {:ok,
         %{
           status: 200,
           headers: [{"content-type", "application/json"}, {"cache-control", "max-age=300"}],
           body: JSON.encode!(document)
         }}
      end
    )
  end
end
