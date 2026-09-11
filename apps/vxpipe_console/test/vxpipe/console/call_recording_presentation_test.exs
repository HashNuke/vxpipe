defmodule Vxpipe.Console.CallRecordingPresentationTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Vxpipe.Calls.{ArchiveStatus, CallDetailPage, CallListPage, CallSummary}

  alias Vxpipe.Console.{
    TestCallInspectionBackend,
    TestCallRecordingBackend,
    TestOperatorAuthenticator
  }

  alias Vxpipe.Console.CallRecording.Summary

  @endpoint Vxpipe.Console.Endpoint
  @tenant_key "tenantkey1234567"

  setup do
    original_authenticator = Application.fetch_env!(:vxpipe_console, :operator_authenticator)
    original_inspection = Application.fetch_env!(:vxpipe_console, :call_inspection_backend)
    original_recording = Application.fetch_env!(:vxpipe_console, :call_recording_backend)

    on_exit(fn ->
      Application.put_env(:vxpipe_console, :operator_authenticator, original_authenticator)
      Application.put_env(:vxpipe_console, :call_inspection_backend, original_inspection)
      Application.put_env(:vxpipe_console, :call_recording_backend, original_recording)
    end)

    Application.put_env(
      :vxpipe_console,
      :operator_authenticator,
      {TestOperatorAuthenticator, self()}
    )

    configure_inspection()
    :ok
  end

  test "renders playable full-mix and aligned-track evidence without storage references" do
    configure_recordings({:ok, [full_mix(), participant_track()]})

    html = sign_in() |> recycle() |> get("/calls/call-public-id") |> html_response(200)

    assert html =~ "Recordings"
    assert html =~ "Full mix"
    assert html =~ "Participant track"
    assert html =~ "Incomplete"
    assert html =~ "1 gap"
    assert html =~ "Starts at 1.000 s"
    assert html =~ "/calls/call-public-id/recordings/full-mix-artifact"
    assert html =~ "/calls/call-public-id/recordings/participant-artifact"
    assert length(Regex.scan(~r/<audio\b/, html)) == 2
    refute html =~ "private/full-mix.s16le"

    assert_receive {:list_call_recordings, principal, "call-public-id"}
    assert principal.tenant_key == @tenant_key
  end

  test "distinguishes no artifacts from unavailable recording evidence" do
    configure_recordings({:ok, []})

    empty_html = sign_in() |> recycle() |> get("/calls/call-public-id") |> html_response(200)

    assert empty_html =~ "No recording artifacts"

    configure_recordings({:error, :repository_unavailable})

    unavailable_html =
      sign_in() |> recycle() |> get("/calls/call-public-id") |> html_response(200)

    assert unavailable_html =~ "Recording evidence unavailable"
    refute unavailable_html =~ "repository_unavailable"
    refute unavailable_html =~ "<audio"
  end

  defp sign_in do
    post(build_conn(), "/operator/session", %{
      "operator" => %{
        "tenant_key" => @tenant_key,
        "api_key" => "valid-api-key"
      }
    })
  end

  defp configure_inspection do
    call = call_summary()

    responses = %{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: nil}},
      inspect_call:
        {:ok,
         %CallDetailPage{
           call: call,
           timeline: [],
           next_cursor: nil,
           archive_status: ArchiveStatus.from_facts([]),
           persisted_variable_revision: 0
         }}
    }

    Application.put_env(
      :vxpipe_console,
      :call_inspection_backend,
      {TestCallInspectionBackend, {self(), responses}}
    )
  end

  defp configure_recordings(response) do
    Application.put_env(
      :vxpipe_console,
      :call_recording_backend,
      {TestCallRecordingBackend, {self(), response}}
    )
  end

  defp call_summary do
    %CallSummary{
      id: "call-public-id",
      tenant_key: @tenant_key,
      definition_id: "definition-public-id",
      definition_revision: 1,
      state: :ended,
      created_at: ~U[2026-09-11 20:00:00Z],
      started_at: ~U[2026-09-11 20:00:01Z],
      ended_at: ~U[2026-09-11 20:00:03Z],
      terminal_reason: "ended",
      latest_variable_revision: 0
    }
  end

  defp full_mix do
    %Summary{
      id: "full-mix-artifact",
      kind: :full_mix,
      participant_id: nil,
      connection_id: nil,
      track_id: nil,
      sample_rate: 8_000,
      channels: 1,
      started_offset_samples: 0,
      ended_offset_samples: 16_000,
      sample_count: 15_900,
      accepted_chunks: 20,
      rejected_chunks: 1,
      gaps: [%{"offset_samples" => 8_000, "sample_count" => 100}],
      status: :incomplete,
      terminal_reason: "source_ended",
      playable?: true
    }
  end

  defp participant_track do
    %Summary{
      id: "participant-artifact",
      kind: :participant_track,
      participant_id: "participant-public-id",
      connection_id: "connection-public-id",
      track_id: "track-public-id",
      sample_rate: 8_000,
      channels: 1,
      started_offset_samples: 8_000,
      ended_offset_samples: 16_000,
      sample_count: 8_000,
      accepted_chunks: 10,
      rejected_chunks: 0,
      gaps: [],
      status: :complete,
      terminal_reason: "source_ended",
      playable?: true
    }
  end
end
