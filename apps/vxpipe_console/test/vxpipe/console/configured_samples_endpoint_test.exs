defmodule Vxpipe.Console.ConfiguredSamplesEndpointTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Vxpipe.Console.Test.FakeUserIdentity
  alias Vxpipe.Persistence.{Repo, CredentialStore, CallSpecStore, CallStore}
  @endpoint Vxpipe.Console.Endpoint

  setup do
    if Process.whereis(Repo) == nil, do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    old_sample = Application.fetch_env!(:vxpipe_console, :sample_call)
    old_backend = Application.get_env(:vxpipe_console, :user_identity_backend)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
      Application.put_env(:vxpipe_console, :sample_call, old_sample)
      Application.put_env(:vxpipe_console, :user_identity_backend, old_backend)
    end)

    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)

    tenant =
      Repo.insert!(
        Vxpipe.Persistence.Schema.Tenant.changeset(%Vxpipe.Persistence.Schema.Tenant{}, %{
          key: "AAAAAAAAAAAAAAAA",
          name: "Sample fixture"
        })
      )

    source = %{
      schema_version: "20261004.01",
      name: "Development sample",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{type: "agent", prompt: "Help.", transfers: ["support"]},
        "support" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "transfer"}
        }
      }
    }

    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}}
    ]

    Application.put_env(:vxpipe_console, :sample_call,
      enabled: true,
      tenant_key: tenant.key,
      call_spec: source,
      initial_variables: %{},
      transfer_participant: "support",
      calls_options: options
    )

    conn =
      post(build_conn(), "https://localhost/auth/api/login", %{
        email: FakeUserIdentity.email(),
        password: FakeUserIdentity.password()
      })

    %{
      conn: conn,
      options: options,
      key_count: Repo.aggregate(Vxpipe.Persistence.Schema.ApiKey, :count)
    }
  end

  test "canonical preparation and legacy transfer use the explicitly selected call", c do
    first =
      c.conn
      |> recycle()
      |> post("https://localhost/api/samples/calls", %{})
      |> json_response(201)

    second =
      c.conn
      |> recycle()
      |> post("https://localhost/admin/samples/calls", %{})
      |> json_response(201)

    refute first["call_id"] == second["call_id"]

    assert c.conn
           |> recycle()
           |> post(
             "https://localhost/api/samples/transfers",
             Map.take(first, ["tenant_key", "call_id"])
           )
           |> json_response(409)

    scope = %{
      tenant_key: first["tenant_key"],
      call_id: first["call_id"],
      participant_key: first["participant_key"]
    }

    assert {:ok, claim} =
             Vxpipe.Calls.claim_join_token(first["join_token"]["token"], scope, c.options)

    assert {:ok, _} =
             Vxpipe.Calls.mark_call_started(claim, "rinc_sample", DateTime.utc_now(), c.options)

    for path <- ["/api/samples/transfers", "/admin/samples/transfers"] do
      transfer =
        c.conn
        |> recycle()
        |> post("https://localhost" <> path, Map.take(first, ["tenant_key", "call_id"]))
        |> json_response(201)

      assert transfer["call_id"] == first["call_id"]
      refute transfer["participant_key"] == first["participant_key"]
    end

    assert Repo.aggregate(Vxpipe.Persistence.Schema.ApiKey, :count) == c.key_count
    assert Repo.aggregate(Vxpipe.Persistence.Schema.CallSpec, :count) == 1
  end

  test "canonical and legacy sample routes reject credentials before parsing and enforce CSRF",
       c do
    for prefix <- ["/api/samples", "/admin/samples"], action <- ["calls", "transfers"] do
      path = "https://localhost" <> prefix <> "/" <> action
      assert build_conn() |> post(path, %{}) |> json_response(401)

      assert c.conn
             |> recycle()
             |> put_req_header("authorization", "Bearer synthetic-key")
             |> put_req_header("content-type", "application/json")
             |> post(path, "not-json")
             |> json_response(401)

      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        c.conn
        |> recycle()
        |> then(&%{&1 | private: Map.delete(&1.private, :plug_skip_csrf_protection)})
        |> put_req_header("x-csrf-token", "invalid")
        |> post(path, %{})
      end
    end

    assert Repo.aggregate(Vxpipe.Persistence.Schema.CallSpec, :count) == 0
  end

  test "known inherited-service authoring denial remains a policy response" do
    assert Vxpipe.Console.SampleAdmissionJSON.error_response(
             %{code: :provider_service_forbidden},
             "sample_call"
           ) == {403, "forbidden"}
  end

  test "repository failures remain bounded safe errors", c do
    settings = Application.fetch_env!(:vxpipe_console, :sample_call)

    Application.put_env(
      :vxpipe_console,
      :sample_call,
      Keyword.put(settings, :calls_options, call_spec_repository: {MissingSampleRepository, nil})
    )

    assert c.conn
           |> recycle()
           |> post("https://localhost/api/samples/calls", %{})
           |> json_response(503) ==
             %{"error" => %{"code" => "sample_call_unavailable"}}
  end

  test "transfer requires explicit tenant and call and disabled remains distinct", c do
    assert c.conn
           |> recycle()
           |> post("https://localhost/api/samples/transfers", %{})
           |> json_response(422) ==
             %{"error" => %{"code" => "invalid_sample_target"}}

    Application.put_env(:vxpipe_console, :sample_call, enabled: false)

    assert c.conn
           |> recycle()
           |> post("https://localhost/api/samples/calls", %{})
           |> json_response(404) ==
             %{"error" => %{"code" => "durable_sample_disabled"}}
  end
end
