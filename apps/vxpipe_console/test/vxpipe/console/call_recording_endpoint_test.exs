defmodule Vxpipe.Console.CallRecordingEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2, put_req_header: 3]

  alias Vxpipe.Calls.CallArtifact

  alias Vxpipe.Console.{
    TestCallRecordingBackend,
    TestCallRecordingReader
  }

  alias Vxpipe.Console.CallRecording.Source

  @endpoint Vxpipe.Console.Endpoint
  @secret String.duplicate("operator-call-recording-secret-", 3)
  @token "operator-call-recording-token"
  @tenant_key "tenantkey1234567"
  @route "/tenants/#{@tenant_key}/calls/call-public-id/recordings/artifact-public-id"

  setup do
    original_calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    original_secret = Application.fetch_env!(:vxpipe_console, :operator_login_secret)
    original_backend = Application.fetch_env!(:vxpipe_console, :call_recording_backend)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, original_calls)
      Application.put_env(:vxpipe_console, :operator_login_secret, original_secret)
      Application.put_env(:vxpipe_console, :call_recording_backend, original_backend)
    end)

    Application.put_env(:vxpipe_console, :operator_login_secret, @secret)
    configure_login_repository()

    :ok
  end

  test "requires an operator session" do
    assert redirected_to(https_get(@route), 302) == "/auth/login"
  end

  test "streams an exact private WAV from the authorized artifact" do
    payload = <<1, 2, 3, 4, 5, 6, 7, 8>>
    configure_recording({:ok, source(payload)})

    conn = authenticate() |> recycle() |> https_get(@route)
    body = response(conn, 200)

    assert <<"RIFF", _rest::binary>> = body
    assert binary_part(body, byte_size(body) - byte_size(payload), byte_size(payload)) == payload
    assert get_resp_header(conn, "content-type") == ["audio/wav"]
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert get_resp_header(conn, "location") == []

    assert_receive {:open_call_recording, access, "call-public-id", "artifact-public-id"}
    assert {:ok, @tenant_key} = Vxpipe.Calls.CallReadAccess.tenant_key(access)
  end

  test "serves one byte range without reading outside it" do
    payload = <<1, 2, 3, 4, 5, 6, 7, 8>>
    configure_recording({:ok, source(payload)})

    conn =
      authenticate()
      |> recycle()
      |> put_req_header("range", "bytes=44-47")
      |> https_get(@route)

    assert response(conn, 206) == <<1, 2, 3, 4>>
    assert get_resp_header(conn, "content-range") == ["bytes 44-47/52"]
    assert_receive {:recording_source_read, 0, 3}
    refute_receive {:recording_source_read, _, _}
  end

  test "returns generic not found for an inaccessible call or artifact" do
    configure_recording({:error, :call_not_found})

    conn = authenticate() |> recycle() |> https_get(@route)

    assert response(conn, 404) == "Recording not found."
    refute conn.resp_body =~ "call_not_found"
  end

  test "rejects an unsatisfiable range without touching object storage" do
    configure_recording({:ok, source(<<1, 2, 3, 4, 5, 6, 7, 8>>)})

    conn =
      authenticate()
      |> recycle()
      |> put_req_header("range", "bytes=99-100")
      |> https_get(@route)

    assert response(conn, 416) == "Requested recording range is unavailable."
    assert get_resp_header(conn, "content-range") == ["bytes */52"]
    refute_receive {:recording_source_read, _, _}
  end

  test "reports an initial object read failure without exposing its reason" do
    configure_recording({:ok, source({:error, :synthetic_secret_storage_failure})})

    conn =
      authenticate()
      |> recycle()
      |> put_req_header("range", "bytes=44-47")
      |> https_get(@route)

    assert response(conn, 502) == "Recording storage is temporarily unavailable."
    refute conn.resp_body =~ "synthetic_secret_storage_failure"
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

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")

  defp csrf_token(body) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, body)
    token
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

  defp configure_recording(response) do
    Application.put_env(
      :vxpipe_console,
      :call_recording_backend,
      {TestCallRecordingBackend, {self(), response}}
    )
  end

  defp source(payload) do
    {:ok, source} =
      Source.new(
        artifact(),
        {TestCallRecordingReader, {self(), payload}}
      )

    source
  end

  defp artifact do
    %CallArtifact{
      id: "artifact-public-id",
      tenant_key: @tenant_key,
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      kind: :full_mix,
      participant_id: nil,
      connection_id: nil,
      track_id: nil,
      object_key: "private/recording.s16le",
      object_reference: %{"object_key" => "private/recording.s16le"},
      sample_rate: 8_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 0,
      ended_offset_samples: 4,
      sample_count: 4,
      accepted_chunks: 1,
      rejected_chunks: 0,
      gaps: [],
      status: :complete,
      terminal_reason: "source_ended"
    }
  end
end
