defmodule Vxpipe.Persistence.OAuthStoreTest do
  use Vxpipe.Persistence.DataCase, async: false
  import Ecto.Query
  alias Vxpipe.Persistence.{IdentityUserStore, OAuthFixtures}
  alias Vxpipe.Persistence.OAuth.Store
  alias Vxpipe.Persistence.OAuth.{Code, Grant, Token}

  setup do
    fixture = OAuthFixtures.browser_user()
    {:ok, client} = Store.register_client(OAuthFixtures.registration())
    {:ok, snapshot} = Store.consent_snapshot(fixture.principal)
    Map.merge(fixture, %{client: client, snapshot: snapshot})
  end

  test "real Boruta code exchange and refresh keep the grant while persisting only digests",
       ctx do
    issued = issue!(ctx)
    assert issued.state == "test-state"
    assert issued.redirect_uri == "http://127.0.0.1:43210/callback"

    assert {:ok, token} =
             Store.exchange(
               OAuthFixtures.exchange(ctx.client.client_id, issued.code),
               OAuthFixtures.resource()
             )

    assert token.token_type == "bearer"
    assert token.expires_in in 598..600
    assert {:ok, identity} = Store.authenticate(token.access_token, OAuthFixtures.resource())
    assert identity.user.public_id == ctx.user.public_id
    assert identity.grant.public_id == issued.grant_id
    assert identity.grant.authority == ctx.snapshot.authority

    assert {:ok, rotated} =
             Store.exchange(
               OAuthFixtures.refresh(ctx.client.client_id, token.refresh_token),
               OAuthFixtures.resource()
             )

    refute rotated.access_token == token.access_token
    refute rotated.refresh_token == token.refresh_token
    assert {:ok, refreshed} = Store.authenticate(rotated.access_token, OAuthFixtures.resource())
    assert refreshed.grant.public_id == identity.grant.public_id
    assert refreshed.grant.expires_at == identity.grant.expires_at

    stored =
      ~w(oauth_clients oauth_grants oauth_codes oauth_tokens)
      |> Enum.map(fn table ->
        Repo.all(from(row in table, select: fragment("row_to_json(?)", row)))
      end)
      |> inspect(limit: :infinity)

    for raw <- [
          issued.code,
          token.access_token,
          token.refresh_token,
          rotated.access_token,
          rotated.refresh_token
        ] do
      refute stored =~ raw
    end
  end

  test "wrong verifier, resource, redirect and client do not consume a valid code", ctx do
    issued = issue!(ctx)
    params = OAuthFixtures.exchange(ctx.client.client_id, issued.code)
    {:ok, other} = Store.register_client(OAuthFixtures.registration())

    for changed <- [
          Map.put(params, "code_verifier", String.duplicate("b", 43)),
          Map.put(params, "resource", "https://wrong.example/mcp"),
          Map.put(params, "redirect_uri", "http://127.0.0.1:43211/callback"),
          Map.put(params, "client_id", other.client_id)
        ] do
      assert {:error, _} = Store.exchange(changed, OAuthFixtures.resource())
    end

    assert {:ok, _} = Store.exchange(params, OAuthFixtures.resource())
    assert {:error, :invalid_grant} = Store.exchange(params, OAuthFixtures.resource())
  end

  test "refresh replay commits family revocation but wrong-client and wrong-resource reuse do not",
       ctx do
    issued = issue!(ctx)

    {:ok, token} =
      Store.exchange(
        OAuthFixtures.exchange(ctx.client.client_id, issued.code),
        OAuthFixtures.resource()
      )

    refresh = OAuthFixtures.refresh(ctx.client.client_id, token.refresh_token)
    {:ok, rotated} = Store.exchange(refresh, OAuthFixtures.resource())
    {:ok, other} = Store.register_client(OAuthFixtures.registration())

    assert {:error, :invalid_grant} =
             Store.exchange(
               Map.put(refresh, "client_id", other.client_id),
               OAuthFixtures.resource()
             )

    assert {:error, :invalid_target} =
             Store.exchange(
               Map.put(refresh, "resource", "https://wrong.example/mcp"),
               OAuthFixtures.resource()
             )

    assert {:ok, _} = Store.authenticate(rotated.access_token, OAuthFixtures.resource())
    assert {:error, :invalid_grant} = Store.exchange(refresh, OAuthFixtures.resource())

    assert {:error, :invalid_token} =
             Store.authenticate(rotated.access_token, OAuthFixtures.resource())

    assert {:error, :invalid_grant} =
             Store.exchange(
               OAuthFixtures.refresh(ctx.client.client_id, rotated.refresh_token),
               OAuthFixtures.resource()
             )
  end

  test "authority version changes invalidate access, refresh and pending consent", ctx do
    issued = issue!(ctx)

    {:ok, token} =
      Store.exchange(
        OAuthFixtures.exchange(ctx.client.client_id, issued.code),
        OAuthFixtures.resource()
      )

    assert {:ok, _} =
             IdentityUserStore.apply_update(ctx.user.public_id, %{
               password_hash: "new-synthetic-hash",
               expected_current_password_hash: "synthetic-oauth-hash"
             })

    assert {:error, :invalid_token} =
             Store.authenticate(token.access_token, OAuthFixtures.resource())

    assert {:error, :invalid_grant} =
             Store.exchange(
               OAuthFixtures.refresh(ctx.client.client_id, token.refresh_token),
               OAuthFixtures.resource()
             )

    assert {:error, _} =
             Store.issue_code(
               ctx.principal,
               OAuthFixtures.authorization(ctx.client.client_id),
               OAuthFixtures.resource(),
               ctx.snapshot
             )
  end

  test "resource binding and explicit token revocation are checked for every access", ctx do
    issued = issue!(ctx)

    {:ok, token} =
      Store.exchange(
        OAuthFixtures.exchange(ctx.client.client_id, issued.code),
        OAuthFixtures.resource()
      )

    assert {:error, :invalid_token} =
             Store.authenticate(token.access_token, "https://wrong.example/mcp")

    {:ok, other} = Store.register_client(OAuthFixtures.registration())

    assert :ok =
             Store.revoke(
               %{"client_id" => other.client_id, "token" => token.refresh_token},
               OAuthFixtures.resource()
             )

    assert {:ok, _} = Store.authenticate(token.access_token, OAuthFixtures.resource())

    assert :ok =
             Store.revoke(
               %{"client_id" => ctx.client.client_id, "token" => token.refresh_token},
               OAuthFixtures.resource()
             )

    assert :ok =
             Store.revoke(
               %{"client_id" => ctx.client.client_id, "token" => "unknown"},
               OAuthFixtures.resource()
             )

    assert {:error, :invalid_token} =
             Store.authenticate(token.access_token, OAuthFixtures.resource())
  end

  test "successor issuance rolls back when code consumption fails", ctx do
    issued = issue!(ctx)
    params = OAuthFixtures.exchange(ctx.client.client_id, issued.code)

    Repo.query!(
      "ALTER TABLE oauth_codes ADD CONSTRAINT oauth_test_no_consume CHECK (consumed_at IS NULL)"
    )

    assert {:error, :unavailable} = Store.exchange(params, OAuthFixtures.resource())
    assert Repo.aggregate(Token, :count) == 0
    assert Repo.get_by!(Code, grant_id: issued.grant_id).consumed_at == nil
    Repo.query!("ALTER TABLE oauth_codes DROP CONSTRAINT oauth_test_no_consume")
    assert {:ok, _} = Store.exchange(params, OAuthFixtures.resource())
  end

  test "access expires independently and grant expiry denies refresh", ctx do
    issued = issue!(ctx)

    {:ok, token} =
      Store.exchange(
        OAuthFixtures.exchange(ctx.client.client_id, issued.code),
        OAuthFixtures.resource()
      )

    past = DateTime.add(DateTime.utc_now(), -1)
    Repo.update_all(Token, set: [access_expires_at: past])

    assert {:error, :invalid_token} =
             Store.authenticate(token.access_token, OAuthFixtures.resource())

    assert {:ok, refreshed} =
             Store.exchange(
               OAuthFixtures.refresh(ctx.client.client_id, token.refresh_token),
               OAuthFixtures.resource()
             )

    Repo.update_all(Grant, set: [expires_at: past])

    assert {:error, :invalid_token} =
             Store.authenticate(refreshed.access_token, OAuthFixtures.resource())

    assert {:error, :invalid_grant} =
             Store.exchange(
               OAuthFixtures.refresh(ctx.client.client_id, refreshed.refresh_token),
               OAuthFixtures.resource()
             )
  end

  test "cleanup removes expired grants and abandoned clients in bounded batches", ctx do
    issued = issue!(ctx)

    {:ok, _} =
      Store.exchange(
        OAuthFixtures.exchange(ctx.client.client_id, issued.code),
        OAuthFixtures.resource()
      )

    assert {:ok, active} = Store.register_client(OAuthFixtures.registration())
    yesterday = DateTime.add(DateTime.utc_now(), -86_401)
    Repo.update_all(Grant, set: [expires_at: yesterday])

    Repo.update_all(
      from(c in "oauth_clients", where: c.public_id == type(^ctx.client.client_id, :binary_id)),
      set: [inserted_at: yesterday]
    )

    assert {:ok, %{grants: 1, clients: 1}} = Store.cleanup(10)
    assert Repo.aggregate(Token, :count) == 0
    assert Repo.aggregate(Code, :count) == 0
    assert Repo.get(Vxpipe.Persistence.OAuth.Client, active.client_id)
    assert {:error, :invalid_limit} = Store.cleanup(1001)
  end

  test "consent belongs to the displayed user even when another user has identical authority",
       ctx do
    other = OAuthFixtures.browser_user()

    assert {:error, :invalid_request} =
             Store.issue_code(
               other.principal,
               OAuthFixtures.authorization(ctx.client.client_id),
               OAuthFixtures.resource(),
               ctx.snapshot
             )

    assert Repo.aggregate(Grant, :count) == 0
  end

  test "expired codes and changed role revisions cannot issue tokens", ctx do
    issued = issue!(ctx)
    Repo.update_all(Code, set: [expires_at: DateTime.add(DateTime.utc_now(), -1)])

    assert {:error, :invalid_grant} =
             Store.exchange(
               OAuthFixtures.exchange(ctx.client.client_id, issued.code),
               OAuthFixtures.resource()
             )

    fresh = issue!(ctx)

    Repo.update_all(
      from(r in Vxpipe.Persistence.Schema.IdentityRole, where: r.id == ^ctx.user.role_id),
      inc: [revision: 1]
    )

    assert {:error, :invalid_grant} =
             Store.exchange(
               OAuthFixtures.exchange(ctx.client.client_id, fresh.code),
               OAuthFixtures.resource()
             )
  end

  test "active grant quota is enforced and bounded cleanup frees expired capacity", ctx do
    issued = issue!(ctx)
    source = Repo.get!(Grant, issued.grant_id)
    attrs = source |> Map.from_struct() |> Map.delete(:__meta__)

    Repo.insert_all(
      Grant,
      Enum.map(1..99, fn _ -> Map.put(attrs, :public_id, Ecto.UUID.generate()) end)
    )

    assert {:error, :quota_exceeded} =
             Store.issue_code(
               ctx.principal,
               OAuthFixtures.authorization(ctx.client.client_id),
               OAuthFixtures.resource(),
               ctx.snapshot
             )

    Repo.update_all(Grant, set: [expires_at: DateTime.add(DateTime.utc_now(), -1)])
    assert {:ok, %{grants: 10}} = Store.cleanup(10)
    assert Repo.aggregate(Grant, :count) == 90

    assert {:ok, _} =
             Store.issue_code(
               ctx.principal,
               OAuthFixtures.authorization(ctx.client.client_id),
               OAuthFixtures.resource(),
               ctx.snapshot
             )
  end

  test "new consent clears its user's abandoned expired code without a new client registration",
       ctx do
    issued = issue!(ctx)
    Repo.update_all(Code, set: [expires_at: DateTime.add(DateTime.utc_now(), -1)])
    fresh = issue!(ctx)
    refute fresh.grant_id == issued.grant_id
    assert Repo.get(Grant, issued.grant_id) == nil
    assert Repo.get(Grant, fresh.grant_id)
  end

  defp issue!(ctx) do
    assert {:ok, issued} =
             Store.issue_code(
               ctx.principal,
               OAuthFixtures.authorization(ctx.client.client_id),
               OAuthFixtures.resource(),
               ctx.snapshot
             )

    issued
  end
end
