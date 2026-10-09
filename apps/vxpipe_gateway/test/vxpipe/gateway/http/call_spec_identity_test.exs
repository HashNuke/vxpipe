defmodule Vxpipe.Gateway.HTTP.CallSpecIdentityTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test
  alias Vxpipe.Calls.{Administration, CallSpecs, TestMemoryRepository}
  alias Vxpipe.Gateway.HTTP.Endpoint

  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: {TestMemoryRepository, repository},
      call_spec_repository: {TestMemoryRepository, repository},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("HTTP identity", [:admin], options)
    {:ok, other, _} = Administration.bootstrap_tenant("Other tenant", [:admin], options)

    endpoint =
      Endpoint.init(
        call_spec_authoring: [enabled: true, backend: {Vxpipe.Gateway.CallSpecAuthoring, options}]
      )

    %{
      options: options,
      endpoint: endpoint,
      tenant: tenant,
      other: other,
      key: key,
      path: "/api/tenants/#{tenant.key}/call-specs"
    }
  end

  test "PUT cannot allocate a client-selected ID, including a well-formed UUID", ctx do
    for id <- ["new", "11111111-1111-4111-8111-111111111111"] do
      response = request(ctx, :put, ctx.path <> "/" <> id, %{"source" => source()})
      assert response.status == 404
      assert JSON.decode!(response.resp_body)["error"]["code"] == "call_spec_not_found"
      assert {:error, :not_found} = CallSpecs.fetch(ctx.tenant.key, id, 1, ctx.options)
    end
  end

  test "POST generates identity, PUT only appends within its tenant, and bodies cannot assign IDs",
       ctx do
    for field <- ["id", "public_id", "call_spec_id"] do
      for {method, suffix} <- [{:post, ""}, {:put, "/new"}] do
        assert request(ctx, method, ctx.path <> suffix, %{
                 "source" => source(),
                 field => "11111111-1111-4111-8111-111111111111"
               }).status == 400
      end
    end

    created = request(ctx, :post, ctx.path, %{"source" => source()})
    assert created.status == 201
    first = JSON.decode!(created.resp_body)["call_spec"]
    id = first["call_spec_id"]
    assert id =~ ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

    updated =
      request(ctx, :put, ctx.path <> "/" <> id, %{
        "source" => Map.put(source(), "name", "Updated")
      })

    assert updated.status == 201
    assert JSON.decode!(updated.resp_body)["call_spec"]["call_spec_id"] == id
    assert JSON.decode!(updated.resp_body)["call_spec"]["revision"] == 2
    assert {:ok, first_revision} = CallSpecs.fetch(ctx.tenant.key, id, 1, ctx.options)
    assert first_revision.source == source()
    {:ok, foreign} = CallSpecs.save(ctx.other.key, source(), ctx.options)

    assert request(ctx, :put, ctx.path <> "/" <> foreign.call_spec_id, %{"source" => source()}).status ==
             404

    assert {:error, :not_found} =
             CallSpecs.fetch(ctx.tenant.key, foreign.call_spec_id, 1, ctx.options)
  end

  defp request(ctx, method, path, body) do
    conn(method, path, JSON.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> ctx.key.secret)
    |> Endpoint.call(ctx.endpoint)
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
        "assistant" => %{"type" => "agent", "prompt" => "Help."}
      }
    }
  end
end
