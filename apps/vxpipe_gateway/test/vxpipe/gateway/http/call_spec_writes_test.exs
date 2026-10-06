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
