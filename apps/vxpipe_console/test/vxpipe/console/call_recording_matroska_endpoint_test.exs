defmodule Vxpipe.Console.CallRecordingMatroskaEndpointTest do
  @moduledoc """
  Matroska recording download backed by real tenant-scoped persistence.

  Two tenants are bootstrapped through `Vxpipe.Calls.Administration` with the
  Ecto stores. The recorded call and its artifacts live under the first
  tenant; the same call id requested under the second tenant returns the
  generic 404 because `ArtifactStore` scopes the lookup by tenant. No
  backend stub masks the cross-tenant boundary.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2]

  alias Vxpipe.Calls.{Administration, CallArtifact}
  alias Vxpipe.Console.{CallsRecordingBackend, RecordingMatroska, TestCallRecordingObjectReader}
  alias Vxpipe.Console.Test.FakeUserIdentity

  alias Vxpipe.Persistence.{
    ArchiveStore,
    ArtifactStore,
    CallSpecStore,
    CallStore,
    CredentialStore,
    Repo
  }

  alias Vxpipe.Persistence.Schema.Call, as: StoredCall

  @endpoint Vxpipe.Console.Endpoint
  @payload_bytes 48_000

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    original_identity = Application.get_env(:vxpipe_console, :user_identity_backend)
    original_backend = Application.fetch_env!(:vxpipe_console, :call_recording_backend)

    on_exit(fn ->
      if original_identity,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, original_identity),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)

      Application.put_env(:vxpipe_console, :call_recording_backend, original_backend)
    end)

    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)

    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      archive_repository: {ArchiveStore, Repo},
      artifact_repository: {ArtifactStore, Repo},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, issued} =
      Administration.bootstrap_tenant("Recorded call tenant", [:calls], options)

    {:ok, other, _issued} =
      Administration.bootstrap_tenant("Other recorded tenant", [:calls], options)

    {:ok, principal} = Administration.authenticate(tenant.key, issued.secret, :calls, options)

    {:ok, draft} = Vxpipe.Calls.save_call_spec(tenant.key, spec_source(), options)

    {:ok, published} =
      Vxpipe.Calls.publish_call_spec(tenant.key, draft.call_spec_id, draft.revision, options)

    route = Enum.find(published.routes, &(&1.participant_ref == "caller"))
    {:ok, prepared, _token} = Vxpipe.Calls.prepare_call(principal, route.key, %{}, options)

    incarnation = "inc-recording-#{System.unique_integer([:positive])}"
    mark_running(tenant.key, prepared.id, incarnation)

    payloads = %{
      "room" => :binary.copy(<<16, 0>>, @payload_bytes),
      "caller" => :binary.copy(<<32, 0>>, @payload_bytes),
      "caller-1" => :binary.copy(<<48, 0>>, @payload_bytes)
    }

    for {name, key} <- [{"room", "room"}, {"caller", "caller"}, {"caller-1", "caller-1"}] do
      artifact =
        case name do
          "room" ->
            room_artifact(tenant.key, prepared.id, prepared.room_id, incarnation, key)

          _ ->
            participant_artifact(
              tenant.key,
              prepared.id,
              prepared.room_id,
              incarnation,
              name,
              key
            )
        end

      assert {:ok, _stored} = ArtifactStore.store_call_artifact(Repo, artifact)
    end

    Application.put_env(
      :vxpipe_console,
      :call_recording_backend,
      {CallsRecordingBackend,
       [
         calls_options: [artifact_repository: {ArtifactStore, Repo}],
         recording_settings: [bucket: "recordings-test"],
         object_reader: TestCallRecordingObjectReader,
         object_reader_options: [observer: self(), payload: payloads]
       ]}
    )

    {:ok, empty_call, _token} = Vxpipe.Calls.prepare_call(principal, route.key, %{}, options)

    %{
      tenant: tenant.key,
      other: other.key,
      call_id: prepared.id,
      empty_call_id: empty_call.id,
      payloads: payloads
    }
  end

  test "requires an operator session" do
    assert json_response(https_get(api_route("exampletenant00001", "call-public-id")), 401)[
             "error"
           ]["code"] ==
             "session_required"

    assert json_response(https_get(browser_route("exampletenant00001", "call-public-id")), 401)[
             "error"
           ]["code"] ==
             "session_required"
  end

  test "streams one aligned Matroska file with attachment disposition", data do
    conn = authenticate() |> recycle() |> https_get(api_route(data.tenant, data.call_id))
    body = response(conn, 200)

    assert binary_part(body, 0, 4) == <<0x1A, 0x45, 0xDF, 0xA3>>
    assert body =~ "room"
    assert body =~ "caller"
    assert body =~ "caller-1"
    assert get_resp_header(conn, "content-type") == ["audio/x-matroska"]
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]

    assert get_resp_header(conn, "content-disposition") == [
             "attachment; filename=\"call-#{data.call_id}.mka\""
           ]

    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert {:ok, [_room, _caller, _reconnect]} = stored_artifacts(data.tenant, data.call_id)
  end

  test "streams the browser route with the same authorization", data do
    conn = authenticate() |> recycle() |> https_get(browser_route(data.tenant, data.call_id))
    body = response(conn, 200)

    assert binary_part(body, 0, 4) == <<0x1A, 0x45, 0xDF, 0xA3>>
    assert get_resp_header(conn, "content-type") == ["audio/x-matroska"]
  end

  test "serves one byte range without reading outside it", data do
    conn =
      authenticate()
      |> recycle()
      |> Plug.Conn.put_req_header("range", "bytes=0-99")
      |> https_get(api_route(data.tenant, data.call_id))

    assert byte_size(response(conn, 206)) == 100
    assert [range] = get_resp_header(conn, "content-range")
    assert String.starts_with?(range, "bytes 0-99/")
  end

  test "serves a range spanning an audio block boundary with exact bytes", data do
    full =
      response(
        authenticate() |> recycle() |> https_get(api_route(data.tenant, data.call_id)),
        200
      )

    matroska = persisted_matroska(data.tenant, data.call_id, data.payloads)

    first_audio = matroska.prefix_size + matroska.cluster_header_len + matroska.block_header_len
    assert first_audio > 7

    first = first_audio - 7
    last = first_audio + 25

    conn =
      authenticate()
      |> recycle()
      |> Plug.Conn.put_req_header("range", "bytes=#{first}-#{last}")
      |> https_get(api_route(data.tenant, data.call_id))

    assert response(conn, 206) == binary_part(full, first, last - first + 1)
    assert get_resp_header(conn, "content-range") == ["bytes #{first}-#{last}/#{byte_size(full)}"]
  end

  test "returns generic not found for an unknown call or an empty recording", data do
    assert response(
             authenticate() |> recycle() |> https_get(api_route(data.tenant, "malformed-id")),
             404
           ) == "Recording not found."

    unknown_call_id = "00000000-0000-4000-8000-000000000000"

    assert response(
             authenticate() |> recycle() |> https_get(api_route(data.tenant, unknown_call_id)),
             404
           ) == "Recording not found."

    assert response(
             authenticate() |> recycle() |> https_get(api_route(data.tenant, data.empty_call_id)),
             404
           ) == "Recording not found."

    assert response(
             authenticate()
             |> recycle()
             |> https_get(browser_route(data.tenant, data.empty_call_id)),
             404
           ) == "Recording not found."
  end

  test "keeps an authorized call inaccessible under another real tenant", data do
    assert response(
             authenticate() |> recycle() |> https_get(api_route(data.tenant, data.call_id)),
             200
           ) =~ "caller-1"

    assert response(
             authenticate() |> recycle() |> https_get(api_route(data.other, data.call_id)),
             404
           ) == "Recording not found."

    assert response(
             authenticate() |> recycle() |> https_get(browser_route(data.other, data.call_id)),
             404
           ) == "Recording not found."
  end

  test "rejects an unsatisfiable range without touching object storage", data do
    full =
      response(
        authenticate() |> recycle() |> https_get(api_route(data.tenant, data.call_id)),
        200
      )

    total = byte_size(full)

    conn =
      authenticate()
      |> recycle()
      |> Plug.Conn.put_req_header("range", "bytes=#{total}-#{total + 100}")
      |> https_get(api_route(data.tenant, data.call_id))

    assert response(conn, 416) == "Requested recording range is unavailable."
    assert get_resp_header(conn, "content-range") == ["bytes */#{total}"]
  end

  defp authenticate do
    post(build_conn(), "https://localhost/auth/api/login", %{
      "email" => FakeUserIdentity.email(),
      "password" => FakeUserIdentity.password()
    })
  end

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")

  defp api_route(tenant_key, call_id),
    do: "/api/tenants/#{tenant_key}/calls/#{call_id}/recording.mka"

  defp browser_route(tenant_key, call_id),
    do: "/tenants/#{tenant_key}/calls/#{call_id}/recording.mka"

  defp stored_artifacts(tenant_key, call_id),
    do: ArtifactStore.fetch_call_artifacts(Repo, tenant_key, call_id)

  defp persisted_matroska(tenant_key, call_id, payloads) do
    {:ok, access} = Vxpipe.Calls.user_call_access(FakeUserIdentity.principal(), tenant_key)

    {:ok, sources} =
      CallsRecordingBackend.open_all(
        [
          calls_options: [artifact_repository: {ArtifactStore, Repo}],
          recording_settings: [bucket: "recordings-test"],
          object_reader: TestCallRecordingObjectReader,
          object_reader_options: [observer: self(), payload: payloads]
        ],
        access,
        call_id
      )

    {:ok, matroska} = RecordingMatroska.new(sources)
    matroska
  end

  defp mark_running(tenant_key, call_id, incarnation) do
    stored = Repo.get_by!(StoredCall, public_id: call_id)
    assert stored.tenant_id == Repo.get_by!(Vxpipe.Persistence.Schema.Tenant, key: tenant_key).id

    {:ok, _} =
      stored
      |> Ecto.Changeset.change(%{state: :running, incarnation_id: incarnation})
      |> Repo.update()
  end

  defp spec_source do
    %{
      schema_version: "20260915.01",
      name: "Matroska endpoint acceptance",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{
        capabilities: %{model_inference: %{provider: "fixture", model: "test:scripted"}}
      },
      call_variables: %{
        sections: %{
          "order" => %{
            schema: %{
              "type" => "object",
              "properties" => %{"id" => %{"type" => "string"}},
              "additionalProperties" => false
            }
          }
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "receiver" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          first_message: %{mode: "wait_for_input"},
          variable_permissions: %{"order" => ["read"]},
          tools: %{"hangup" => %{type: "platform", tool: "hangup"}},
          transfers: []
        }
      }
    }
  end

  defp room_artifact(tenant_key, call_id, room_id, incarnation, object_key) do
    %CallArtifact{
      id: "artifact-room",
      tenant_key: tenant_key,
      call_id: call_id,
      room_id: room_id,
      incarnation_id: incarnation,
      kind: :room_track,
      participant_id: nil,
      connection_id: nil,
      track_id: nil,
      participant_key: nil,
      reconnection: 0,
      object_key: object_key,
      object_reference: %{"object_key" => object_key},
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 0,
      ended_offset_samples: @payload_bytes,
      sample_count: @payload_bytes,
      accepted_chunks: 1,
      rejected_chunks: 0,
      gaps: [],
      status: :complete,
      terminal_reason: "source_ended"
    }
  end

  defp participant_artifact(tenant_key, call_id, room_id, incarnation, name, object_key) do
    reconnection = if name == "caller-1", do: 1, else: 0

    %CallArtifact{
      id: "artifact-#{name}",
      tenant_key: tenant_key,
      call_id: call_id,
      room_id: room_id,
      incarnation_id: incarnation,
      kind: :participant_track,
      participant_id: "part_caller",
      connection_id: "conn_#{name}",
      track_id: "track_#{name}",
      participant_key: "caller",
      reconnection: reconnection,
      object_key: object_key,
      object_reference: %{"object_key" => object_key},
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 0,
      ended_offset_samples: @payload_bytes,
      sample_count: @payload_bytes,
      accepted_chunks: 1,
      rejected_chunks: 0,
      gaps: [],
      status: :complete,
      terminal_reason: "source_ended"
    }
  end
end
