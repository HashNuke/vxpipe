defmodule Vxpipe.Gateway.HTTP.CallSpecWritesTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test
  alias Vxpipe.Calls.{InstallationOperator, Principal}
  alias Vxpipe.Gateway.HTTP.Endpoint

  @tenant "AAAAAAAAAAAAAAAA"
  @operator "/api/platform/tenants/#{@tenant}/call-specs"
  @tenant_path "/api/tenants/#{@tenant}/call-specs"

  test "routes create, update and publish with the authenticated principal and safe responses" do
    for {path, key, kind} <- [
          {@operator, "operator-key", InstallationOperator},
          {@tenant_path, "tenant-key", Principal}
        ] do
      created = request(:post, path, key, %{"source" => %{"name" => "Example"}})
      assert created.status == 201
      assert_receive {:save, author, @tenant, %{"name" => "Example"}, nil}
      assert is_struct(author, kind)
      assert JSON.decode!(created.resp_body)["call_spec"]["revision"] == 1
      refute created.resp_body =~ "must-not-echo"
      assert get_resp_header(created, "cache-control") == ["no-store"]

      assert request(:put, path <> "/existing", key, %{"source" => %{}}).status == 201
      assert_receive {:save, ^author, @tenant, %{}, "existing"}

      published = request(:post, path <> "/existing/revisions/2/publish", key, %{})
      assert published.status == 200
      assert_receive {:publish, ^author, @tenant, "existing", 2}
      assert JSON.decode!(published.resp_body)["call_spec"]["published"]
    end
  end

  test "rejects missing, wrong-scope and calls-only keys before any authoring operation" do
    for {path, key, status} <- [
          {@operator, nil, 401},
          {@operator, "tenant-key", 401},
          {@tenant_path, "operator-key", 401},
          {@tenant_path, "calls-only", 403},
          {String.replace(@tenant_path, @tenant, "BBBBBBBBBBBBBBBB"), "tenant-key", 401}
        ] do
      assert request(:post, path, key, %{"source" => %{}}).status == status
    end

    refute_received {:save, _, _, _, _}
    refute_received {:publish, _, _, _, _}
  end

  test "input cannot inject authority or options, and publication needs a positive revision" do
    for body <- [
          %{"source" => %{}, "service_authoring_owner" => "platform"},
          %{"source" => [], "authority" => "operator"},
          %{}
        ] do
      assert request(:post, @tenant_path, "tenant-key", body).status == 400
    end

    for revision <- ["0", "-1", "not-a-revision"] do
      assert request(
               :post,
               @operator <> "/existing/revisions/#{revision}/publish",
               "operator-key",
               %{}
             ).status == 400
    end

    assert request(:post, @operator <> "/existing/revisions/1/publish", "operator-key", %{
             "source" => %{}
           }).status == 400

    assert request(:put, @operator <> "/" <> String.duplicate("a", 129), "operator-key", %{
             "source" => %{}
           }).status == 400

    refute_received {:save, _, _, _, _}
    refute_received {:publish, _, _, _, _}
  end

  test "scope-denied service references return 403 without exposing backend details" do
    error =
      Vxpipe.CallEngine.Error.new(:provider_service_forbidden, "private backend message",
        details: %{"private" => "do-not-echo"}
      )

    response = request(:post, @tenant_path, "tenant-key", %{"source" => %{}}, {:error, error})
    assert response.status == 403
    assert JSON.decode!(response.resp_body)["error"]["code"] == "provider_service_forbidden"
    refute response.resp_body =~ "private"
    refute response.resp_body =~ "do-not-echo"
  end

  test "a missing outgoing caller ID is reported as such, not as a credential failure" do
    error =
      Vxpipe.CallEngine.Error.new(:telephony_caller_id_missing, "private backend message",
        details: %{"path" => ["participants", "callee", "connection", "service"]}
      )

    response =
      request(:post, @tenant_path <> "/existing/revisions/1/publish", "tenant-key", %{}, {
        :error,
        error
      })

    assert response.status == 422
    assert JSON.decode!(response.resp_body)["error"]["code"] == "telephony_caller_id_missing"

    assert JSON.decode!(response.resp_body)["error"]["path"] == [
             "participants",
             "callee",
             "connection",
             "service"
           ]

    refute response.resp_body =~ "private"
  end

  test "backend failures become a safe unavailable response" do
    response = request(:post, @operator, "operator-key", %{"source" => %{}}, :crash)
    assert response.status == 503

    assert JSON.decode!(response.resp_body) == %{
             "error" => %{"code" => "call_spec_authoring_unavailable"}
           }

    refute response.resp_body =~ "private"
  end

  test "invalid sources return the validator's field path and reason on create and update" do
    incoming = source()

    outgoing =
      incoming
      |> Map.delete("incoming_call")
      |> Map.put("outgoing_call", %{"callee" => "caller", "handled_by" => "assistant"})
      |> put_in(["participants", "caller", "connection"], %{
        "service" => "phone",
        "mode" => "dial",
        "number" => "+15550001000"
      })

    cases = [
      {update_in(incoming, ["participants", "assistant"], &Map.delete(&1, "prompt")),
       ["participants", "assistant", "prompt"]},
      {put_in(incoming, ["incoming_call", "handled_by"], "missing"),
       ["incoming_call", "handled_by"]},
      {put_in(outgoing, ["participants", "assistant"], %{
         "type" => "human",
         "connection" => %{"service" => "web", "mode" => "receive", "admission" => "transfer"}
       }), ["outgoing_call", "handled_by"]},
      {put_in(outgoing, ["outgoing_call", "ring_timeout_ms"], 1),
       ["outgoing_call", "ring_timeout_ms"]},
      {put_in(outgoing, ["participants", "caller", "connection", "number"], "private-number"),
       ["participants", "caller", "connection", "number"]},
      {put_in(incoming, ["participants", "assistant", "transfers"], ["missing"]),
       ["participants", "assistant", "transfers", "0"]},
      {put_in(incoming, ["participants", "assistant", "tools"], %{
         "transfer" => %{"type" => "platform", "name" => "transfer"}
       }), ["participants", "assistant", "tools", "transfer"]}
    ]

    for {source, path} <- cases do
      assert {:error, error} =
               Vxpipe.CallEngine.CallSpec.new(source, resource_id: "test", revision: 1)

      assert error.details["path"] == path

      for {method, route} <- [{:post, @tenant_path}, {:put, @tenant_path <> "/existing"}] do
        response = request(method, route, "tenant-key", %{"source" => source}, {:error, error})
        assert response.status == 422

        assert JSON.decode!(response.resp_body) == %{
                 "error" => %{
                   "code" => "invalid_call_spec",
                   "path" => path,
                   "reason" => error.details["reason"]
                 }
               }

        refute response.resp_body =~ "private-number"
      end
    end
  end

  test "save and publish preserve specific failures with fixed public explanations" do
    for {failure, status, code} <- [
          {:revision_conflict, 409, "revision_conflict"},
          {:revision_generation_exhausted, 409, "revision_conflict"},
          {:invalid_telephony_route, 422, "invalid_telephony_route"},
          {:private_call_spec_material, 422, "private_call_spec_material"}
        ] do
      for {route, body} <- [
            {@tenant_path, %{"source" => %{}}},
            {@tenant_path <> "/existing/revisions/1/publish", %{}}
          ] do
        response = request(:post, route, "tenant-key", body, {:error, failure})

        assert response.status == status

        assert %{"code" => ^code, "path" => [], "reason" => reason} =
                 JSON.decode!(response.resp_body)["error"]

        assert is_binary(reason) and reason != ""
      end
    end
  end

  test "publication and saved validation errors expose only the first compiler error" do
    error =
      Vxpipe.CallEngine.Error.new(:unsupported_call_plan, "private-message",
        details: %{
          "path" => ["participants", "assistant", "tools", "lookup"],
          "reason" => "does not resolve to an available host tool",
          "secret" => "private-secret"
        }
      )

    errors = [Vxpipe.CallEngine.Error.to_public(error), %{"reason" => "private-second"}]

    response =
      request(
        :post,
        @tenant_path <> "/existing/revisions/1/publish",
        "tenant-key",
        %{},
        {:error, {:call_spec_not_publishable, errors}}
      )

    assert response.status == 409

    assert JSON.decode!(response.resp_body)["error"] == %{
             "code" => "call_spec_not_publishable",
             "path" => error.details["path"],
             "reason" => error.details["reason"]
           }

    revision = %Vxpipe.Calls.CallSpecRevision{
      tenant_key: @tenant,
      call_spec_id: "id",
      revision: 1,
      schema_version: "20261004.01",
      source: %{},
      source_digest: "digest",
      compiled_metadata: %{},
      validation_errors: errors,
      routes: [],
      telephony_routes: [],
      published_at: nil,
      inserted_at: DateTime.utc_now()
    }

    saved = request(:post, @tenant_path, "tenant-key", %{"source" => %{}}, {:ok, revision})

    assert [%{"code" => "unsupported_call_plan", "path" => path, "reason" => reason}] =
             JSON.decode!(saved.resp_body)["call_spec"]["validation_errors"]

    assert path == error.details["path"]
    assert reason == error.details["reason"]
    refute response.resp_body =~ "private"
    refute saved.resp_body =~ "private"
  end

  test "invalid values never appear in field error responses" do
    for source <- [
          put_in(
            source(),
            ["participants", "assistant", "prompt"],
            String.duplicate("secret-prompt", 3000)
          ),
          Map.put(source(), "opening_audio", %{
            "type" => "file_url",
            "url" => "https://secret-user:secret-pass@example.com/audio?signature=private"
          })
        ] do
      assert {:error, error} =
               Vxpipe.CallEngine.CallSpec.new(source, resource_id: "test", revision: 1)

      response =
        request(:post, @tenant_path, "tenant-key", %{"source" => source}, {:error, error})

      assert response.status == 422
      assert is_list(JSON.decode!(response.resp_body)["error"]["path"])
      refute response.resp_body =~ "secret-"
      refute response.resp_body =~ "signature="
    end
  end

  defp source do
    %{
      "schema_version" => "20261004.01",
      "incoming_call" => %{"caller" => "caller", "handled_by" => "assistant"},
      "participants" => %{
        "caller" => %{
          "type" => "human",
          "connection" => %{"service" => "web", "mode" => "receive", "admission" => "start_call"}
        },
        "assistant" => %{"type" => "agent", "prompt" => "Help the caller."}
      }
    }
  end

  defp request(method, path, key, body, result \\ nil) do
    options =
      Endpoint.init(
        call_spec_authoring: [
          enabled: true,
          backend: {Vxpipe.Gateway.TestCallSpecAuthoringBackend, {self(), result}}
        ]
      )

    conn =
      conn(method, path, JSON.encode!(body)) |> put_req_header("content-type", "application/json")

    conn = if key, do: put_req_header(conn, "authorization", "Bearer " <> key), else: conn
    Endpoint.call(conn, options)
  end
end
