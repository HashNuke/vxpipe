defmodule Vxpipe.Console.VoiceCatalogEndpointTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  alias Vxpipe.Calls.{ProviderCredential, ResolvedProviderCredential}
  alias Vxpipe.Console.Test.FakeUserIdentity
  @endpoint Vxpipe.Console.Endpoint
  @tenant "AAAAAAAAAAAAAAAA"
  @base "/admin/api/tenants/#{@tenant}/providers/morse_code_api/voices"
  @query "?capability=text_to_speech&model=morse_v1&credential_name=speech"

  setup do
    calls = Application.get_env(:vxpipe_calls, Vxpipe.Calls)
    identity = Application.get_env(:vxpipe_console, :user_identity_backend)
    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(calls, :provider_credential_repository, {__MODULE__, self()})
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, calls)

      if identity,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, identity),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)
    end)

    :ok
  end

  test "authenticated descriptors, paged list and direct lookup share the scoped contract" do
    auth =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => FakeUserIdentity.email(),
        "password" => FakeUserIdentity.password()
      })

    for {suffix, expected} <- [
          {"/descriptor", "providerName"},
          {"", "voices"},
          {"/morse", "voice"}
        ] do
      conn = auth |> recycle() |> get("https://localhost" <> @base <> suffix <> @query)
      assert Map.has_key?(json_response(conn, 200), expected)
      assert Plug.Conn.get_resp_header(conn, "cache-control") == ["no-store"]
      refute conn.resp_body =~ "private-test"
      assert_received {:resolved, @tenant, "morse_code_api", "speech"}
    end

    conn = auth |> recycle() |> get("https://localhost" <> @base <> "/missing" <> @query)
    assert json_response(conn, 200) == %{"voice" => nil}
  end

  test "anonymous callers and malformed queries cannot discover voices" do
    assert json_response(get(build_conn(), "https://localhost" <> @base <> @query), 401)["error"][
             "code"
           ] == "session_required"

    refute_received {:resolved, _, _, _}

    auth =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => FakeUserIdentity.email(),
        "password" => FakeUserIdentity.password()
      })

    for suffix <- ["&filters=not-json", "&filters=%5B%5D", "&search[]=bad", "&cursor[]=bad"] do
      conn = auth |> recycle() |> get("https://localhost" <> @base <> @query <> suffix)
      assert json_response(conn, 422)["error"]["code"] == "invalid_voice_query"
    end
  end

  def resolve(owner, tenant, provider, name) do
    send(owner, {:resolved, tenant, provider, name})

    {:ok,
     %ResolvedProviderCredential{
       credential: %ProviderCredential{
         id: "1",
         tenant_key: tenant,
         provider: provider,
         name: name,
         auth_kind: "api_key"
       },
       payload: %{"api_key" => "private-test"}
     }}
  end
end
