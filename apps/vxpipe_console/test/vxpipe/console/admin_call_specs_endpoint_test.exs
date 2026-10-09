defmodule Vxpipe.Console.AdminCallSpecsEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Vxpipe.Calls.{CallSpecSummary, Tenant}

  @endpoint Vxpipe.Console.Endpoint
  @secret String.duplicate("operator-admin-call-specs-secret-", 3)
  @token "operator-admin-call-specs-token"
  @tenant_key "AAAAAAAAAAAAAAAA"

  setup do
    original_calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    original_secret = Application.fetch_env!(:vxpipe_console, :operator_login_secret)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, original_calls)
      Application.put_env(:vxpipe_console, :operator_login_secret, original_secret)
    end)

    Application.put_env(:vxpipe_console, :operator_login_secret, @secret)
    configure_login_repository()
    :ok
  end

  test "returns one tenant-scoped call spec page to an installation operator" do
    tenant = %Tenant{
      key: @tenant_key,
      name: "Example tenant",
      inserted_at: ~U[2026-09-17 01:00:00Z]
    }

    call_specs = [
      %CallSpecSummary{
        id: "delivery-rescheduling",
        name: "Delivery rescheduling",
        latest_revision: 4,
        published_revision: 3,
        call_count: 5,
        updated_at: ~U[2026-09-17 03:00:00Z]
      }
    ]

    configure_admin_repository({:ok, {tenant, call_specs, 26}})

    conn =
      authenticate()
      |> recycle()
      |> get("/admin/api/tenants/#{@tenant_key}/call-specs?page=2")

    assert json_response(conn, 200) == %{
             "tenant" => %{"key" => @tenant_key, "name" => "Example tenant"},
             "call_specs" => [
               %{
                 "id" => "delivery-rescheduling",
                 "name" => "Delivery rescheduling",
                 "latest_revision" => 4,
                 "published_revision" => 3,
                 "call_count" => 5,
                 "updated_at" => "2026-09-17T03:00:00Z"
               }
             ],
             "pagination" => %{
               "page" => 2,
               "page_size" => 25,
               "total" => 26,
               "total_pages" => 2
             }
           }

    assert_received {:operator_call_specs_requested, @tenant_key, 25, 25}
  end

  test "distinguishes missing tenant, unavailable storage, invalid pages, and anonymous access" do
    configure_admin_repository({:error, :tenant_not_found})
    missing = authenticate() |> recycle() |> https_get("/admin/api/tenants/missing/call-specs")
    assert json_response(missing, 404) == %{"error" => %{"code" => "tenant_not_found"}}
    assert_received {:operator_call_specs_requested, "missing", 25, 0}

    configure_admin_repository({:error, :database_unavailable})

    unavailable =
      authenticate() |> recycle() |> https_get("/admin/api/tenants/#{@tenant_key}/call-specs")

    assert json_response(unavailable, 503) == %{
             "error" => %{"code" => "call_spec_directory_unavailable"}
           }

    assert_received {:operator_call_specs_requested, @tenant_key, 25, 0}

    configure_admin_repository(
      {:ok,
       {%Tenant{key: @tenant_key, name: "Example", inserted_at: ~U[2026-09-17 01:00:00Z]}, [], 0}}
    )

    invalid =
      authenticate()
      |> recycle()
      |> get("/admin/api/tenants/#{@tenant_key}/call-specs?page[]=1")

    assert json_response(invalid, 422) == %{"error" => %{"code" => "invalid_page"}}
    refute_received {:operator_call_specs_requested, _, _, _}

    anonymous = https_get("/admin/api/tenants/#{@tenant_key}/call-specs")
    assert json_response(anonymous, 401) == %{"error" => %{"code" => "operator_session_required"}}
  end

  describe "editor authoring" do
    setup do
      alias Vxpipe.Persistence.{Repo, CredentialStore, CallSpecStore}
      if Process.whereis(Repo) == nil, do: start_supervised!(Repo)
      owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
      settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

      options = [
        credential_repository: {CredentialStore, Repo},
        call_spec_repository: {CallSpecStore, Repo},
        registries: %{host_tools: %{}}
      ]

      Application.put_env(:vxpipe_calls, Vxpipe.Calls, Keyword.merge(settings, options))
      {:ok, tenant, _} = Vxpipe.Calls.bootstrap_tenant("Editor tenant", [:admin])
      {:ok, other, _} = Vxpipe.Calls.bootstrap_tenant("Other editor tenant", [:admin])
      %{tenant: tenant, other: other, authenticated: authenticate()}
    end

    test "creates, publishes, appends and reads immutable tenant-scoped source revisions", %{
      tenant: tenant,
      other: other,
      authenticated: auth
    } do
      path = "/admin/api/tenants/#{tenant.key}/call-specs"
      source = editor_source()
      created = write(auth, :post, path, %{"source" => source})
      first = json_response(created, 201)["call_spec"]
      assert first["revision"] == 1
      assert first["source"] == source
      assert first["validation_errors"] == []
      assert [%{"participant_ref" => "caller", "published" => false}] = first["routes"]
      assert Plug.Conn.get_resp_header(created, "cache-control") == ["private, no-store"]
      id = first["call_spec_id"]
      assert id =~ ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

      published = write(auth, :post, path <> "/#{id}/revisions/1/publish", %{})
      assert json_response(published, 200)["call_spec"]["published"]
      changed = Map.put(source, "name", "Changed in editor")
      second = write(auth, :put, path <> "/#{id}", %{"source" => changed})
      assert json_response(second, 201)["call_spec"]["revision"] == 2
      latest = auth |> recycle() |> https_get(path <> "/#{id}") |> json_response(200)
      assert latest["call_spec"]["source"] == changed
      assert latest["call_spec"]["published_revision"] == 1
      assert latest["call_spec"]["latest_revision"] == 2

      historical =
        auth |> recycle() |> https_get(path <> "/#{id}?revision=1") |> json_response(200)

      assert historical["call_spec"]["source"] == source
      assert historical["call_spec"]["source_digest"] == first["source_digest"]
      assert historical["call_spec"]["published"]
      assert historical["call_spec"]["published_revision"] == 1

      foreign = "/admin/api/tenants/#{other.key}/call-specs/#{id}"

      for response <- [
            auth |> recycle() |> https_get(foreign),
            write(auth, :put, foreign, %{"source" => source}),
            write(auth, :post, foreign <> "/revisions/1/publish", %{})
          ] do
        assert json_response(response, 404)["error"]["code"] == "call_spec_not_found"
      end
    end

    test "projects field errors and rejects secret material without returning values", %{
      tenant: tenant,
      authenticated: auth
    } do
      path = "/admin/api/tenants/#{tenant.key}/call-specs"
      invalid = put_in(editor_source(), ["participants", "assistant", "prompt"], "")
      response = write(auth, :post, path, %{"source" => invalid})

      assert %{
               "error" => %{
                 "code" => "invalid_call_spec",
                 "path" => ["participants", "assistant", "prompt"],
                 "reason" => reason
               }
             } = json_response(response, 422)

      assert is_binary(reason)
      private = Map.put(editor_source(), "api_key", "private-editor-sentinel")
      response = write(auth, :post, path, %{"source" => private})
      assert json_response(response, 422)["error"]["code"] == "private_call_spec_material"
      refute response.resp_body =~ "private-editor-sentinel"
    end

    test "preserves large integer enums in portable source returned to the editor", %{
      tenant: tenant,
      authenticated: auth
    } do
      source =
        Map.put(editor_source(), "call_variables", %{
          "sections" => %{
            "account" => %{
              "schema" => %{
                "type" => "object",
                "properties" => %{
                  "external_id" => %{"type" => "integer", "enum" => [9_007_199_254_740_993]}
                }
              }
            }
          }
        })

      path = "/admin/api/tenants/#{tenant.key}/call-specs"
      saved = write(auth, :post, path, %{"source" => source}) |> json_response(201)
      assert saved["call_spec"]["source"] == source
      assert saved["call_spec"]["validation_errors"] == []
      id = saved["call_spec"]["call_spec_id"]
      read = auth |> recycle() |> https_get(path <> "/#{id}") |> json_response(200)
      assert read["call_spec"]["source"] == source
    end

    test "identity is generated on creation and cannot be assigned through authoring input", %{
      tenant: tenant,
      authenticated: auth
    } do
      path = "/admin/api/tenants/#{tenant.key}/call-specs"

      for id <- ["new", "11111111-1111-4111-8111-111111111111"] do
        assert {:error, :not_found} =
                 Vxpipe.Calls.save_authorized_call_spec(
                   Vxpipe.Calls.InstallationOperator.authority(),
                   tenant.key,
                   editor_source(),
                   call_spec_id: id
                 )

        response = write(auth, :put, path <> "/" <> id, %{"source" => editor_source()})
        assert json_response(response, 404)["error"]["code"] == "call_spec_not_found"
      end

      for field <- ["id", "public_id", "call_spec_id"] do
        response = write(auth, :post, path, %{"source" => editor_source(), field => "new"})
        assert json_response(response, 400)["error"]["code"] == "invalid_request"
      end
    end

    test "rejects malformed requests and unavailable revisions", %{
      tenant: tenant,
      authenticated: auth
    } do
      path = "/admin/api/tenants/#{tenant.key}/call-specs"
      created = write(auth, :post, path, %{"source" => editor_source()}) |> json_response(201)
      id = created["call_spec"]["call_spec_id"]

      for body <- [%{}, %{"source" => []}, %{"source" => editor_source(), "revision" => 12}] do
        assert write(auth, :post, path, body) |> json_response(400) == %{
                 "error" => %{"code" => "invalid_request"}
               }
      end

      for revision <- ["0", "-1", "x", "2147483648", "1&revision[]=2"] do
        response = auth |> recycle() |> https_get(path <> "/#{id}?revision=#{revision}")
        assert json_response(response, 400)["error"]["code"] == "invalid_request"
      end

      assert auth |> recycle() |> https_get(path <> "/#{id}?revision=99") |> json_response(404) ==
               %{"error" => %{"code" => "call_spec_not_found"}}

      response = write(auth, :post, path <> "/#{id}/revisions/1/publish", %{"unexpected" => true})
      assert json_response(response, 400)["error"]["code"] == "invalid_request"
    end

    test "editor lookups return only effective credential names and tenant application choices",
         %{tenant: tenant, other: other, authenticated: auth} do
      alias Vxpipe.Calls.{
        InstallationOperator,
        OperatorTelephonyApplications,
        ProviderCredentials
      }

      alias Vxpipe.Persistence.{
        AdminStore,
        CredentialKeyring,
        ProviderCredentialStore,
        Repo,
        TelephonyServiceStore
      }

      {:ok, keyring} =
        CredentialKeyring.new("editor", %{"editor" => :crypto.strong_rand_bytes(32)})

      settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

      Application.put_env(
        :vxpipe_calls,
        Vxpipe.Calls,
        Keyword.merge(settings,
          provider_credential_repository:
            {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
          admin_repository: {AdminStore, Repo},
          telephony_service_repository: {TelephonyServiceStore, [repo: Repo, keyring: keyring]}
        )
      )

      for {owner, name} <- [
            {:platform, "shared"},
            {tenant.key, "primary"},
            {other.key, "foreign"}
          ] do
        assert {:ok, _} =
                 ProviderCredentials.provision(
                   owner,
                   "google",
                   name,
                   "api_key",
                   %{"api_key" => "private-lookup-sentinel"},
                   []
                 )
      end

      assert {:ok, _} =
               ProviderCredentials.provision(
                 :platform,
                 "telnyx",
                 "telnyx",
                 "api_key",
                 %{
                   "api_key" => "synthetic-carrier-key",
                   "public_key" => Base.encode64(<<1::256>>)
                 },
                 []
               )

      authority = InstallationOperator.authority()

      assert {:ok, _} =
               OperatorTelephonyApplications.create(authority, tenant.key, %{
                 "name" => "office",
                 "provider_connection_id" => "application-one"
               })

      assert {:ok, _} =
               OperatorTelephonyApplications.create(authority, other.key, %{
                 "name" => "foreign",
                 "provider_connection_id" => "application-two"
               })

      response =
        auth
        |> recycle()
        |> https_get("/admin/api/tenants/#{tenant.key}/call-spec-editor-lookups")

      data = json_response(response, 200)
      assert data["tenant"]["key"] == tenant.key
      assert data["credential_names"]["google"] == ["primary", "shared"]
      assert data["telephony_services"] == [%{"key" => "office", "name" => "office"}]
      assert data["mcp_integrations"] == []
      assert data["truncated"] == false
      refute response.resp_body =~ "private-lookup-sentinel"
      refute response.resp_body =~ "api_key"
      refute response.resp_body =~ "application-one"
      refute response.resp_body =~ "foreign"
      anonymous = https_get("/admin/api/tenants/#{tenant.key}/call-spec-editor-lookups")
      assert json_response(anonymous, 401)["error"]["code"] == "operator_session_required"
    end

    test "publish projects the stored compiler error and storage faults remain value-free", %{
      tenant: tenant,
      authenticated: auth
    } do
      path = "/admin/api/tenants/#{tenant.key}/call-specs"

      source =
        put_in(editor_source(), ["participants", "assistant", "tools"], %{
          "lookup" => %{"type" => "host", "tool" => "unregistered"}
        })

      saved = write(auth, :post, path, %{"source" => source}) |> json_response(201)
      assert [error] = saved["call_spec"]["validation_errors"]
      id = saved["call_spec"]["call_spec_id"]

      published =
        write(auth, :post, path <> "/#{id}/revisions/1/publish", %{}) |> json_response(409)

      assert published["error"]["code"] == "call_spec_not_publishable"
      assert published["error"]["path"] == error["path"]
      assert published["error"]["reason"] == error["reason"]
      settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

      Application.put_env(
        :vxpipe_calls,
        Vxpipe.Calls,
        Keyword.put(settings, :call_spec_repository, {__MODULE__, "private-failure-sentinel"})
      )

      for response <- [
            auth |> recycle() |> https_get(path <> "/#{id}"),
            write(auth, :post, path, %{"source" => editor_source()})
          ] do
        assert json_response(response, 503) == %{
                 "error" => %{"code" => "call_spec_authoring_unavailable"}
               }

        refute response.resp_body =~ "private-failure-sentinel"
      end
    end

    test "does not log portable source contents", %{tenant: tenant, authenticated: auth} do
      source =
        put_in(
          editor_source(),
          ["participants", "assistant", "prompt"],
          "private-prompt-sentinel"
        )

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert write(auth, :post, "/admin/api/tenants/#{tenant.key}/call-specs", %{
                   "source" => source
                 })
                 |> json_response(201)
        end)

      refute log =~ "private-prompt-sentinel"
    end

    test "requires an operator session and CSRF for writes", %{
      tenant: tenant,
      authenticated: auth
    } do
      path = "/admin/api/tenants/#{tenant.key}/call-specs"
      anonymous = post(build_conn(), "https://localhost" <> path, %{"source" => editor_source()})
      assert json_response(anonymous, 401)["error"]["code"] == "operator_session_required"

      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        auth
        |> recycle()
        |> then(&%{&1 | private: Map.delete(&1.private, :plug_skip_csrf_protection)})
        |> Plug.Conn.put_req_header("x-csrf-token", "invalid")
        |> post("https://localhost" <> path, %{"source" => editor_source()})
      end
    end
  end

  defp editor_source do
    %{
      "schema_version" => "20261004.01",
      "name" => "Editor spec",
      "incoming_call" => %{"caller" => "caller", "handled_by" => "assistant"},
      "defaults" => %{
        "capabilities" => %{"model_inference" => %{"provider" => "fixture", "model" => "test"}}
      },
      "participants" => %{
        "caller" => %{
          "type" => "human",
          "connection" => %{"service" => "web", "mode" => "receive", "admission" => "start_call"}
        },
        "assistant" => %{
          "type" => "agent",
          "prompt" => "Help the caller.",
          "tools" => %{},
          "transfers" => []
        }
      }
    }
  end

  defp write(auth, method, path, body) do
    page = auth |> recycle() |> https_get("/admin")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)
    conn = auth |> recycle() |> Plug.Conn.put_req_header("x-csrf-token", csrf)

    case method do
      :post -> post(conn, "https://localhost" <> path, body)
      :put -> put(conn, "https://localhost" <> path, body)
    end
  end

  defp authenticate do
    form = https_get("/auth/login-token/#{@token}")

    form
    |> recycle()
    |> post("https://localhost/auth/login-token", %{
      "_csrf_token" => csrf_token(form.resp_body),
      "operator" => %{"token" => @token, "code" => "01234567"}
    })
  end

  defp configure_login_repository do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(settings, :operator_login_challenge_repository, {
        Vxpipe.Console.Test.OperatorLoginChallengeRepository,
        {self(), :ok}
      })
    )
  end

  defp configure_admin_repository(result) do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(settings, :admin_repository, {
        Vxpipe.Console.Test.AdminRepository,
        {self(), result}
      })
    )
  end

  defp csrf_token(body) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, body)
    token
  end

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")
end
