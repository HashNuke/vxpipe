defmodule Vxpipe.Console.CallInspectionEndpointTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Vxpipe.Calls.{
    ArchiveStatus,
    CallDetailPage,
    CallListPage,
    CallSummary,
    CallTimelineEntry,
    LiveCallInspection
  }

  alias Vxpipe.Console.{
    TestCallInspectionBackend,
    TestOperatorAuthenticator
  }

  @endpoint Vxpipe.Console.Endpoint
  @tenant_key "tenantkey1234567"

  setup do
    original_authenticator = Application.fetch_env!(:vxpipe_console, :operator_authenticator)
    original_backend = Application.fetch_env!(:vxpipe_console, :call_inspection_backend)

    on_exit(fn ->
      Application.put_env(:vxpipe_console, :operator_authenticator, original_authenticator)
      Application.put_env(:vxpipe_console, :call_inspection_backend, original_backend)
    end)

    Application.put_env(
      :vxpipe_console,
      :operator_authenticator,
      {TestOperatorAuthenticator, self()}
    )

    :ok
  end

  test "requires an operator session only for the call-inspection route" do
    calls_conn = get(build_conn(), "/calls")

    assert redirected_to(calls_conn, 302) == "/operator/sign-in"

    sample_conn = get(build_conn(), "/")
    refute sample_conn.status in [301, 302, 303, 307, 308]

    diagnostics = Application.fetch_env!(:vxpipe_console, :diagnostics)

    Application.put_env(:vxpipe_console, :diagnostics, Keyword.put(diagnostics, :enabled, true))
    on_exit(fn -> Application.put_env(:vxpipe_console, :diagnostics, diagnostics) end)

    assert html_response(get(build_conn(), "/diagnostics"), 200) =~ "Vxpipe diagnostics"
  end

  test "signs in with a calls-scoped API key without reflecting the secret" do
    configure_list_response(%CallListPage{calls: [], next_cursor: nil})

    sign_in_page = get(build_conn(), "/operator/sign-in")
    html = html_response(sign_in_page, 200)

    assert html =~ "Tenant key"
    assert html =~ "API key"
    assert html =~ "Sign in to inspect calls"

    conn =
      post(build_conn(), "/operator/session", %{
        "operator" => %{
          "tenant_key" => @tenant_key,
          "api_key" => "valid-api-key"
        }
      })

    assert redirected_to(conn, 302) == "/calls"
    assert_receive {:operator_authentication, @tenant_key, "valid-api-key"}
    refute conn.resp_body =~ "valid-api-key"

    calls_conn = conn |> recycle() |> get("/calls")
    calls_html = html_response(calls_conn, 200)

    assert calls_html =~ "Vxpipe Calls"
    assert calls_html =~ "No calls to inspect"
    assert_receive {:list_calls, _, [limit: 25]}
  end

  test "parses an actual browser form body before CSRF verification" do
    configure_list_response(%CallListPage{calls: [], next_cursor: nil})

    sign_in_page = get(build_conn(), "/operator/sign-in")
    html = html_response(sign_in_page, 200)

    [csrf_token] =
      Regex.run(~r/name="_csrf_token" value="([^"]+)"/, html, capture: :all_but_first)

    body =
      URI.encode_query(%{
        "_csrf_token" => csrf_token,
        "operator[api_key]" => "valid-api-key",
        "operator[tenant_key]" => @tenant_key
      })

    conn =
      sign_in_page
      |> recycle()
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/operator/session", body)

    assert redirected_to(conn, 302) == "/calls"
    assert_receive {:operator_authentication, @tenant_key, "valid-api-key"}
  end

  test "shows a generic recovery message for rejected credentials" do
    conn =
      post(build_conn(), "/operator/session", %{
        "operator" => %{
          "tenant_key" => @tenant_key,
          "api_key" => "rejected-secret"
        }
      })

    html = html_response(conn, 422)

    assert html =~ "Credentials were not accepted"
    assert html =~ @tenant_key
    refute html =~ "rejected-secret"
    refute html =~ "invalid_api_key"
  end

  test "filters the submitted API key from request logs" do
    secret = "request-log-secret-sentinel"

    log =
      capture_log([level: :debug], fn ->
        conn =
          post(build_conn(), "/operator/session", %{
            "operator" => %{
              "tenant_key" => @tenant_key,
              "api_key" => secret
            }
          })

        assert response(conn, 422)
      end)

    assert log =~ "[FILTERED]"
    refute log =~ secret
  end

  test "renders bounded call summaries without private call payloads" do
    call = call_summary()
    configure_list_response(%CallListPage{calls: [call], next_cursor: "next-page"})

    conn = sign_in()
    calls_conn = conn |> recycle() |> get("/calls")
    html = html_response(calls_conn, 200)

    assert html =~ "call-public-id"
    assert html =~ "definition-public-id"
    assert html =~ "Running record"
    assert html =~ "Load older calls"
    refute html =~ "resolved_plan"
    refute html =~ "initial_variables"
  end

  test "distinguishes an unavailable call archive from an empty list" do
    configure_backend(%{list_calls: {:error, :repository_unavailable}})

    conn = sign_in()
    calls_conn = conn |> recycle() |> get("/calls")
    html = html_response(calls_conn, 200)

    assert html =~ "Call archive unavailable"
    assert html =~ "Calls in progress are unaffected"
    refute html =~ "repository_unavailable"
  end

  test "renders escaped persisted evidence and honest archive status for an ended call" do
    call = %{call_summary() | state: :ended, ended_at: ~U[2026-09-09 16:31:00Z]}

    inert_remote_payload =
      timeline_entry(:persisted, :tool_call_completed, %{
        payload: %{
          "result" => "<script>not executable</script>",
          "resource" => %{"uri" => "https://untrusted.invalid/resource"}
        }
      })

    configure_backend(%{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: nil}},
      inspect_call: {:ok, %{persisted_detail(call) | timeline: [inert_remote_payload]}}
    })

    conn = sign_in()
    detail_conn = conn |> recycle() |> get("/calls/#{call.id}")
    html = html_response(detail_conn, 200)

    assert html =~ "Call evidence"
    assert html =~ "Persisted"
    assert html =~ "tool call completed"
    assert html =~ "Archive not yet confirmed"
    assert html =~ "&lt;script&gt;not executable&lt;/script&gt;"
    assert html =~ "https://untrusted.invalid/resource"
    refute html =~ "<script>not executable</script>"
    refute html =~ ~s(href="https://untrusted.invalid/resource")
    refute html =~ ~s(src="https://untrusted.invalid/resource")
    assert_receive {:inspect_call, _, "call-public-id", [limit: 50]}
    refute_receive {:inspect_live_call, _, _, _}
  end

  test "keeps live and persisted variable revisions visibly distinct" do
    call = call_summary()

    configure_backend(%{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: nil}},
      inspect_call: {:ok, persisted_detail(call)},
      inspect_live_call: {:ok, live_detail()}
    })

    conn = sign_in()
    detail_conn = conn |> recycle() |> get("/calls/#{call.id}")
    html = html_response(detail_conn, 200)

    assert html =~ "Live revision"
    assert html =~ "r3"
    assert html =~ "Persisted revision"
    assert html =~ "r2"
    assert html =~ "1 record dropped"
    assert html =~ "Live and persisted evidence available"
    assert_receive {:inspect_live_call, _, "call-public-id", []}
  end

  test "distinguishes a persisted running record from an available live runtime" do
    call = call_summary()

    configure_backend(%{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: nil}},
      inspect_call: {:ok, persisted_detail(call)},
      inspect_live_call: {:error, :call_not_live}
    })

    conn = sign_in()
    html = html_response(conn |> recycle() |> get("/calls/#{call.id}"), 200)

    assert html =~ "Runtime unavailable"
    assert html =~ "Persisted running record; live runtime unavailable"
    assert html =~ "End time unavailable"
    refute html =~ "In progress"
    assert_receive {:inspect_live_call, _, "call-public-id", []}
  end

  test "keeps bounded live evidence available while persisted history is unavailable" do
    call = call_summary()

    configure_backend(%{
      list_calls: {:error, :repository_unavailable},
      inspect_call: {:error, :repository_unavailable},
      inspect_live_call: {:ok, live_detail()}
    })

    conn = sign_in()
    html = html_response(conn |> recycle() |> get("/calls/#{call.id}"), 200)

    assert html =~ "Live evidence available"
    assert html =~ "agent output generated"
    assert html =~ "Persisted revision"
    assert html =~ "Unavailable"
    assert html =~ "Calls in progress are unaffected"
    assert_receive {:inspect_live_call, _, "call-public-id", []}
  end

  test "selects exact sourced evidence and preserves bounded pagination context" do
    call = call_summary()

    selected =
      timeline_entry(:persisted, :tool_call_completed, %{
        id: "persisted-tool-result",
        source_sequence: 7,
        payload: %{"result" => "selected persisted result"}
      })

    persisted = %{
      persisted_detail(call)
      | timeline: [selected],
        next_cursor: "earlier-history"
    }

    live = %{
      live_detail()
      | timeline: [
          timeline_entry(:live, :accepted_input, %{
            id: "live-input",
            source_sequence: 9,
            payload: %{"transcript" => "current live input"}
          })
        ]
    }

    configure_backend(%{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: "older-calls"}},
      inspect_call: {:ok, persisted},
      inspect_live_call: {:ok, live}
    })

    query =
      URI.encode_query(%{
        "cursor" => "current-call-page",
        "event" => "persisted:persisted-tool-result",
        "history_cursor" => "current-history-page"
      })

    conn = sign_in()
    html = html_response(conn |> recycle() |> get("/calls/#{call.id}?#{query}"), 200)

    assert html =~ ~s(data-event-key="persisted:persisted-tool-result")
    assert html =~ ~s(aria-current="true")
    assert html =~ "selected persisted result"
    refute html =~ ~s(aria-current="true" data-event-key="live:live-input")
    assert html =~ "Source"
    assert html =~ "Persisted"
    assert html =~ "Source sequence"
    assert html =~ "Activation"
    assert html =~ "Source participant"
    assert html =~ "Command"
    assert html =~ "Turn"
    assert html =~ "Duration basis"
    assert html =~ "source timestamps"
    assert html =~ "Load older calls"
    assert html =~ "cursor=older-calls"
    assert html =~ "Load earlier events"
    assert html =~ "history_cursor=earlier-history"
    assert html =~ "event=persisted%3Apersisted-tool-result"
  end

  test "renders the permitted variable change between persisted and live revisions" do
    call = call_summary()

    persisted_snapshot =
      timeline_entry(:persisted, :variable_snapshot, %{
        id: "persisted-variables-r2",
        source_sequence: nil,
        variable_revision: 2,
        section_revision: 2,
        payload: %{
          "order" => %{
            "revision" => 2,
            "value" => %{"status" => "pending", "postal_code" => "12345"}
          }
        }
      })

    live_snapshot =
      timeline_entry(:live, :variable_snapshot, %{
        id: "live-variables-r3",
        source_sequence: nil,
        variable_revision: 3,
        section_revision: 3,
        payload: %{
          "order" => %{
            "revision" => 3,
            "value" => %{"status" => "confirmed", "postal_code" => "12345"}
          }
        }
      })

    configure_backend(%{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: nil}},
      inspect_call: {:ok, %{persisted_detail(call) | timeline: [persisted_snapshot]}},
      inspect_live_call: {:ok, %{live_detail() | timeline: [live_snapshot]}}
    })

    conn = sign_in()
    html = html_response(conn |> recycle() |> get("/calls/#{call.id}"), 200)

    assert html =~ "Variables changed"
    assert html =~ "r2 → r3"
    assert html =~ ~s(&quot;before&quot;:&quot;pending&quot;)
    assert html =~ ~s(&quot;after&quot;:&quot;confirmed&quot;)
    refute html =~ "Not projected"
  end

  test "shows bounded persisted duplicate and missing-sequence provenance" do
    call = %{call_summary() | state: :ended, ended_at: ~U[2026-09-09 16:31:00Z]}

    archive_status = %{
      ArchiveStatus.from_facts([])
      | state: :incomplete,
        missing_sequence_count: 2,
        missing_sequences: [4, 5],
        duplicate_id_count: 1,
        duplicate_ids: ["event-duplicate"],
        duplicate_sequence_count: 1,
        duplicate_sequences: [8]
    }

    unknown_tool =
      timeline_entry(:persisted, :tool_call_failed, %{
        id: "tool-unknown",
        payload: %{"name" => "slow_lookup", "reason" => "unknown"}
      })

    persisted = %{
      persisted_detail(call)
      | archive_status: archive_status,
        timeline: [unknown_tool]
    }

    configure_backend(%{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: nil}},
      inspect_call: {:ok, persisted}
    })

    conn = sign_in()
    html = html_response(conn |> recycle() |> get("/calls/#{call.id}"), 200)

    assert html =~ "Archive gap: 2 missing sequences"
    assert html =~ "1 duplicate ID"
    assert html =~ "1 duplicate sequence"
    assert html =~ "tool call failed"
    assert html =~ ~s(&quot;reason&quot;:&quot;unknown&quot;)
  end

  test "returns a safe not-found state when neither retained nor live evidence exists" do
    configure_backend(%{
      list_calls: {:ok, %CallListPage{calls: [], next_cursor: nil}},
      inspect_call: {:error, :call_not_found},
      inspect_live_call: {:error, :call_not_live}
    })

    conn = sign_in()
    html = html_response(conn |> recycle() |> get("/calls/purged-public-id"), 200)

    assert html =~ "Call not found"
    assert html =~ "No retained call is visible to this tenant"
    refute html =~ "call_not_found"
    refute html =~ "call_not_live"
    assert_receive {:inspect_live_call, _, "purged-public-id", []}
  end

  test "changes selected evidence without reloading bounded call sources" do
    call = call_summary()

    configure_backend(%{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: nil}},
      inspect_call: {:ok, persisted_detail(call)},
      inspect_live_call: {:ok, live_detail()}
    })

    conn = sign_in()
    {:ok, view, _html} = live(recycle(conn), "/calls/#{call.id}")
    flush_inspection_messages()

    html = render_patch(view, "/calls/#{call.id}?event=live%3Aevent-public-id")

    assert html =~ ~s(data-event-key="live:event-public-id")
    assert html =~ ~s(aria-current="true")
    refute_receive {:list_calls, _, _}
    refute_receive {:inspect_call, _, _, _}
    refute_receive {:inspect_live_call, _, _, _}
  end

  test "refreshes only the bounded live projection for a connected running call" do
    call = call_summary()

    configure_backend(%{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: nil}},
      inspect_call: {:ok, persisted_detail(call)},
      inspect_live_call: {:ok, live_detail()}
    })

    conn = sign_in()
    {:ok, view, _html} = live(recycle(conn), "/calls/#{call.id}")
    flush_inspection_messages()

    assert_receive {:inspect_live_call, _, "call-public-id", []}, 1_500
    _ = :sys.get_state(view.pid)
    refute_receive {:inspect_call, _, _, _}
    refute_receive {:list_calls, _, _}
    assert render(view) =~ "Live and persisted evidence available"
  end

  test "stops polling and exposes uncertainty when a live runtime disappears" do
    call = call_summary()

    available_responses = %{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: nil}},
      inspect_call: {:ok, persisted_detail(call)},
      inspect_live_call: {:ok, live_detail()}
    }

    configure_backend(available_responses)

    conn = sign_in()
    {:ok, view, _html} = live(recycle(conn), "/calls/#{call.id}")
    flush_inspection_messages()

    configure_backend(%{available_responses | inspect_live_call: {:error, :call_not_live}})

    assert_receive {:inspect_live_call, _, "call-public-id", []}, 1_500
    _ = :sys.get_state(view.pid)

    html = render(view)
    assert html =~ "Runtime unavailable"
    assert html =~ "End time unavailable"
    refute html =~ "In progress"
    refute_receive {:inspect_live_call, _, "call-public-id", []}, 1_200
  end

  test "stops live refresh work when the inspection page closes" do
    call = call_summary()

    configure_backend(%{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: nil}},
      inspect_call: {:ok, persisted_detail(call)},
      inspect_live_call: {:ok, live_detail()}
    })

    conn = sign_in()
    {:ok, view, _html} = live(recycle(conn), "/calls/#{call.id}")
    flush_inspection_messages()

    monitor = Process.monitor(view.pid)
    :ok = GenServer.stop(view.pid)
    assert_receive {:DOWN, ^monitor, :process, _pid, :normal}
    refute_receive {:inspect_live_call, _, "call-public-id", []}, 1_200
  end

  test "reconnects through bounded reads without republishing stale page evidence" do
    call = call_summary()

    previous_live = %{
      live_detail()
      | timeline: [
          timeline_entry(:live, :tool_call_completed, %{
            payload: %{"result" => "stale-page-evidence"}
          })
        ]
    }

    configure_backend(%{
      list_calls: {:ok, %CallListPage{calls: [call], next_cursor: nil}},
      inspect_call: {:ok, persisted_detail(call)},
      inspect_live_call: {:ok, previous_live}
    })

    conn = sign_in()
    {:ok, first_view, first_html} = live(recycle(conn), "/calls/#{call.id}")

    assert first_html =~ "stale-page-evidence"
    assert_receive {:list_calls, _, [limit: 25]}
    assert_receive {:inspect_call, _, "call-public-id", [limit: 50]}
    assert_receive {:inspect_live_call, _, "call-public-id", []}

    monitor = Process.monitor(first_view.pid)
    :ok = GenServer.stop(first_view.pid)
    assert_receive {:DOWN, ^monitor, :process, _pid, :normal}

    configure_backend(%{
      list_calls: {:ok, %CallListPage{calls: [], next_cursor: nil}},
      inspect_call: {:error, :call_not_found},
      inspect_live_call: {:error, :call_not_live}
    })

    {:ok, _reconnected_view, reconnected_html} = live(recycle(conn), "/calls/#{call.id}")

    assert reconnected_html =~ "Call not found"
    refute reconnected_html =~ "stale-page-evidence"
    assert_receive {:list_calls, _, [limit: 25]}
    assert_receive {:inspect_call, _, "call-public-id", [limit: 50]}
    assert_receive {:inspect_live_call, _, "call-public-id", []}
  end

  defp sign_in do
    post(build_conn(), "/operator/session", %{
      "operator" => %{
        "tenant_key" => @tenant_key,
        "api_key" => "valid-api-key"
      }
    })
  end

  defp configure_list_response(page), do: configure_backend(%{list_calls: {:ok, page}})

  defp configure_backend(responses) do
    Application.put_env(
      :vxpipe_console,
      :call_inspection_backend,
      {TestCallInspectionBackend, {self(), responses}}
    )
  end

  defp call_summary do
    %CallSummary{
      id: "call-public-id",
      tenant_key: @tenant_key,
      definition_id: "definition-public-id",
      definition_revision: 3,
      state: :running,
      created_at: ~U[2026-09-09 16:30:00Z],
      started_at: ~U[2026-09-09 16:30:01Z],
      ended_at: nil,
      terminal_reason: nil,
      latest_variable_revision: 2
    }
  end

  defp persisted_detail(call) do
    %CallDetailPage{
      call: call,
      timeline: [timeline_entry(:persisted, :tool_call_completed)],
      next_cursor: nil,
      archive_status: ArchiveStatus.from_facts([]),
      persisted_variable_revision: 2
    }
  end

  defp live_detail do
    %LiveCallInspection{
      tenant_key: @tenant_key,
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      timeline: [timeline_entry(:live, :agent_output_generated)],
      latest_fact_sequence: 8,
      live_variable_revision: 3,
      dropped_records: 1,
      rejected_records: 0
    }
  end

  defp timeline_entry(source, kind, overrides \\ %{}) do
    defaults = %{
      id: "event-public-id",
      kind: kind,
      source: source,
      source_sequence: 8,
      occurred_at: ~U[2026-09-09 16:30:05Z],
      participant_id: "assistant-public-id",
      activation_id: "activation-public-id",
      source_participant_id: "caller-public-id",
      connection_id: nil,
      command_id: "command-public-id",
      correlation_id: "turn-public-id",
      tool_call_id: "tool-public-id",
      variable_revision: nil,
      section_revision: nil,
      payload: %{"result" => "<script>not executable</script>"},
      observed_duration_ms: 320,
      duration_basis: :source_timestamps
    }

    struct!(CallTimelineEntry, Map.merge(defaults, overrides))
  end

  defp flush_inspection_messages do
    receive do
      {:list_calls, _, _} ->
        flush_inspection_messages()

      {operation, _, _, _} when operation in [:inspect_call, :inspect_live_call] ->
        flush_inspection_messages()
    after
      0 -> :ok
    end
  end
end
