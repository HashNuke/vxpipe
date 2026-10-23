defmodule Vxpipe.Persistence.OAuthBrowserTest do
  use Vxpipe.Persistence.DataCase, async: false
  import Ecto.Query
  alias Vxpipe.Persistence.{IdentityUserStore, OAuthFixtures}

  alias Vxpipe.Persistence.OAuth.{
    AuthorizationRequest,
    Browser,
    Client,
    Grant,
    Store,
    Transaction
  }

  setup do
    fixture = OAuthFixtures.browser_user()
    {:ok, client} = Store.register_client(OAuthFixtures.registration())
    Map.merge(fixture, %{client: client, binding: Transaction.random()})
  end

  test "consent is browser/session bound and approval produces exactly one usable code", ctx do
    id = begin!(ctx)
    assert {:error, :invalid_request} = Browser.consent(id, Transaction.random(), ctx.principal)
    assert {:ok, consent} = Browser.consent(id, ctx.binding, ctx.principal)
    assert consent.client_name == "Local OAuth test"
    assert consent.authority["account_kind"] == "superadmin"

    assert {:ok, issued} =
             Browser.complete_authorization(id, ctx.binding, ctx.principal, :approve)

    assert issued.state == "test-state"

    assert {:ok, _} =
             Store.exchange(
               OAuthFixtures.exchange(ctx.client.client_id, issued.code),
               OAuthFixtures.resource()
             )

    assert {:error, :invalid_request} =
             Browser.complete_authorization(id, ctx.binding, ctx.principal, :approve)
  end

  test "approval requires a displayed snapshot and cannot move to a different signed-in user",
       ctx do
    id = begin!(ctx)

    assert {:error, :invalid_request} =
             Browser.complete_authorization(id, ctx.binding, ctx.principal, :approve)

    assert {:ok, _} = Browser.consent(id, ctx.binding, ctx.principal)
    other = OAuthFixtures.browser_user()
    assert {:error, :invalid_request} = Browser.consent(id, ctx.binding, other.principal)

    assert {:error, :invalid_request} =
             Browser.complete_authorization(id, ctx.binding, other.principal, :approve)

    assert Repo.aggregate(Grant, :count) == 0
  end

  test "changed authority and expired transactions cannot approve", ctx do
    id = begin!(ctx)
    assert {:ok, _} = Browser.consent(id, ctx.binding, ctx.principal)

    assert {:ok, _} =
             IdentityUserStore.apply_update(ctx.user.public_id, %{
               password_hash: "changed-synthetic-hash",
               expected_current_password_hash: "synthetic-oauth-hash"
             })

    assert {:error, _} = Browser.complete_authorization(id, ctx.binding, ctx.principal, :approve)
    assert Repo.aggregate(Grant, :count) == 0

    fresh = OAuthFixtures.browser_user()
    fresh = Map.merge(ctx, fresh)
    expired = begin!(fresh)

    Repo.update_all("oauth_authorization_requests",
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1)]
    )

    assert {:error, :invalid_request} = Browser.consent(expired, fresh.binding, fresh.principal)
  end

  test "denial is single use and only returns the validated callback", ctx do
    id = begin!(ctx)
    assert {:ok, _} = Browser.consent(id, ctx.binding, ctx.principal)
    assert {:ok, response} = Browser.complete_authorization(id, ctx.binding, ctx.principal, :deny)

    assert response == %{
             error: "access_denied",
             state: "test-state",
             redirect_uri: "http://127.0.0.1:43210/callback"
           }

    assert {:error, _} = Browser.complete_authorization(id, ctx.binding, ctx.principal, :approve)

    params =
      Map.put(
        OAuthFixtures.authorization(ctx.client.client_id),
        "redirect_uri",
        "https://attacker.example/callback"
      )

    assert {:error, :invalid_request} =
             Browser.begin_authorization(params, OAuthFixtures.resource(), ctx.binding)

    assert Repo.aggregate(Grant, :count) == 0
  end

  test "connected clients expose safe own-grant metadata and revocation checks ownership", ctx do
    id = begin!(ctx)
    {:ok, _} = Browser.consent(id, ctx.binding, ctx.principal)
    {:ok, issued} = Browser.complete_authorization(id, ctx.binding, ctx.principal, :approve)

    {:ok, token} =
      Store.exchange(
        OAuthFixtures.exchange(ctx.client.client_id, issued.code),
        OAuthFixtures.resource()
      )

    assert {:ok, [grant]} = Browser.list_grants(ctx.principal)
    assert grant.public_id == issued.grant_id
    assert grant.client_name == "Local OAuth test"
    refute Map.has_key?(grant, :authority)
    other = OAuthFixtures.browser_user()
    assert {:ok, []} = Browser.list_grants(other.principal)
    assert {:error, :not_found} = Browser.revoke_grant(other.principal, issued.grant_id)
    assert {:ok, _} = Store.authenticate(token.access_token, OAuthFixtures.resource())
    assert :ok = Browser.revoke_grant(ctx.principal, issued.grant_id)

    assert {:error, :invalid_token} =
             Store.authenticate(token.access_token, OAuthFixtures.resource())

    assert {:ok, []} = Browser.list_grants(ctx.principal)
  end

  test "pending requests have a browser quota and store no raw binding or request token", ctx do
    ids = Enum.map(1..10, fn _ -> begin!(ctx) end)

    assert {:error, :quota_exceeded} =
             Browser.begin_authorization(
               OAuthFixtures.authorization(ctx.client.client_id),
               OAuthFixtures.resource(),
               ctx.binding
             )

    stored =
      Repo.all(from(r in "oauth_authorization_requests", select: fragment("row_to_json(?)", r)))
      |> inspect(limit: :infinity)

    refute stored =~ ctx.binding
    for id <- ids, do: refute(stored =~ id)
  end

  test "expired request backlog cannot permanently consume browser quota", ctx do
    begin!(ctx)
    source = Repo.one!(Vxpipe.Persistence.OAuth.AuthorizationRequest)

    attrs =
      source
      |> Map.from_struct()
      |> Map.delete(:__meta__)
      |> Map.put(:expires_at, DateTime.add(DateTime.utc_now(), -1))

    Repo.delete_all(Vxpipe.Persistence.OAuth.AuthorizationRequest)

    Repo.insert_all(
      Vxpipe.Persistence.OAuth.AuthorizationRequest,
      Enum.map(1..111, fn _ ->
        Map.put(attrs, :digest, Transaction.digest(Transaction.random()))
      end)
    )

    assert {:ok, _} =
             Browser.begin_authorization(
               OAuthFixtures.authorization(ctx.client.client_id),
               OAuthFixtures.resource(),
               ctx.binding
             )
  end

  test "unused client retention preserves pending consent until request expiry", ctx do
    Repo.update_all(from(c in Client, where: c.public_id == ^ctx.client.client_id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -86_401)]
    )

    id = begin!(ctx)
    assert {:ok, %{clients: 0, grants: 0}} = Store.cleanup(10)
    assert {:ok, _} = Browser.consent(id, ctx.binding, ctx.principal)

    Repo.update_all(AuthorizationRequest,
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1)]
    )

    assert {:ok, %{clients: 1, grants: 0}} = Store.cleanup(10)
    assert {:error, :invalid_request} = Browser.consent(id, ctx.binding, ctx.principal)
  end

  test "browser actions fail closed for malformed or non-browser principals", ctx do
    id = begin!(ctx)

    for principal <- [nil, %{}, %{ctx.principal | credential_kind: :oauth}] do
      assert {:error, _} = Browser.consent(id, ctx.binding, principal)
      assert {:error, _} = Browser.complete_authorization(id, ctx.binding, principal, :approve)
      assert {:error, _} = Browser.list_grants(principal)
      assert {:error, _} = Browser.revoke_grant(principal, Ecto.UUID.generate())
    end

    assert Repo.aggregate(Grant, :count) == 0
  end

  defp begin!(ctx) do
    assert {:ok, id} =
             Browser.begin_authorization(
               OAuthFixtures.authorization(ctx.client.client_id),
               OAuthFixtures.resource(),
               ctx.binding
             )

    id
  end
end
