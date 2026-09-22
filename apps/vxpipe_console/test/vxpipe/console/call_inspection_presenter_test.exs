defmodule Vxpipe.Console.CallInspectionPresenterTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.{CapabilitySelection, ConnectionIntent}

  alias Vxpipe.CallEngine.ResolvedCallPlan

  alias Vxpipe.CallEngine.ResolvedCallPlan.{
    Capabilities,
    Participant,
    ToolBinding
  }

  alias Vxpipe.CallEngine.Usage.{Attribution, EffectiveAmount, ProviderContext}

  alias Vxpipe.Calls.{
    CallFact,
    CallHistory,
    CallSummary,
    PreparedCall,
    UsageReport,
    VariableSnapshot,
    VariableSnapshotHistory
  }

  alias Vxpipe.Console.{CallInspectionPresenter, CallInspectionResult}

  @tenant_key "tenantkey1234567"

  test "converts complete database state into the versioned snapshot" do
    response = CallInspectionPresenter.present(result())

    assert response["schema_version"] == 1
    refute Map.has_key?(response, "older_cursor")
    refute Map.has_key?(response, "as_of")

    assert response["call"] == %{
             "id" => "call-public-id",
             "revision" => 4,
             "state" => "ended",
             "created_at" => "2026-09-16T09:00:00.000Z",
             "started_at" => "2026-09-16T09:00:01.000Z",
             "ended_at" => "2026-09-16T09:01:31.000Z",
             "terminal_reason" => "completed",
             "duration_ms" => 90_000
           }

    assert response["incarnation"] == %{
             "room_id" => "room-public-id",
             "incarnation_id" => "incarnation-public-id"
           }

    assert [caller, assistant, support] = response["participants"]
    assert caller["id"] == "caller-runtime"
    assert caller["revision"] == 6
    assert caller["value"]["role"] == "caller"
    assert caller["value"]["state"] == "left"
    assert caller["value"]["connection"] == %{"kind" => "webrtc"}

    assert caller["value"]["capabilities"] == [
             %{"name" => "STT", "provider" => "morse", "model" => "morse"}
           ]

    assert assistant["value"]["role"] == "agent"
    assert assistant["id"] == "assistant-runtime"
    assert assistant["revision"] == 0
    assert assistant["value"]["system_prompt"] == "Help the caller."

    assert assistant["value"]["capabilities"] == [
             %{
               "name" => "LLM",
               "provider" => "google",
               "model" => "gemini-2.5-flash"
             },
             %{"name" => "TTS", "provider" => "morse", "model" => "morse"}
           ]

    assert assistant["value"]["tools"] == [
             %{"name" => "lookup_order", "description" => ""}
           ]

    assert assistant["value"]["transfer_policies"] == [
             %{"name" => "support", "description" => ""}
           ]

    assert support["value"]["role"] == "human"
    assert support["value"]["capabilities"] == []
    refute Map.has_key?(response, "participant_configuration")

    assert Enum.map(response["timeline"], & &1["kind"]) == [
             "message",
             "activity",
             "tool-call",
             "message",
             "activity"
           ]

    [input, transcription, tool_call, output, left] = response["timeline"]
    assert input["value"]["text"] == "I need help"
    assert input["value"]["participant_id"] == "caller-runtime"
    assert transcription["value"]["text"] == "Participant transcription final"

    assert tool_call["id"] == "tool-1"
    assert tool_call["revision"] == 4
    assert tool_call["value"]["status"] == "completed"
    assert tool_call["value"]["request"] == %{}
    assert tool_call["value"]["response"] == %{"ok" => true}
    assert tool_call["value"]["response_status"] == 200

    assert output["value"]["text"] == "I found it"
    assert left["value"]["text"] == "Caller left"

    assert response["variables"] == %{
             "state" => "available",
             "value" => %{
               "revision" => 4,
               "sections" => %{
                 "order" => %{
                   "revision" => 2,
                   "value" => %{"status" => "ready"}
                 }
               }
             }
           }

    assert [metric] = response["metrics"]
    assert String.starts_with?(metric["id"], "metric:")
    assert metric["revision"] == 0
    assert metric["value"]["value"] == 42
    assert metric["value"]["unit"] == "tokens"

    assert metric["value"]["scope"] == %{
             "kind" => "participant-capability",
             "participant_id" => "assistant-runtime",
             "capability" => "LLM"
           }

    assert response["completeness"]["state"] == "unconfirmed"

    encoded = JSON.encode!(response)
    refute encoded =~ @tenant_key
    refute encoded =~ "credential_name"
    refute encoded =~ "private-credential-selector"
    refute encoded =~ "source_policy"
  end

  test "presents capability selections archived before model became a top-level field" do
    inspection = result()
    prepared_call = inspection.prepared_call
    plan = prepared_call.plan
    caller = Map.fetch!(plan.participants, "caller")

    archived_selection = %{
      __struct__: CapabilitySelection,
      kind: :speech_to_text,
      provider: Vxpipe.Providers.Deepgram.Flux,
      profile: "deepgram-flux-stt",
      options: %{model: "flux-general-en"}
    }

    capabilities = %{caller.capabilities | speech_to_text: archived_selection}
    caller = %{caller | capabilities: capabilities}
    plan = %{plan | participants: Map.put(plan.participants, "caller", caller)}
    inspection = %{inspection | prepared_call: %{prepared_call | plan: plan}}

    [presented_caller | _rest] = CallInspectionPresenter.present(inspection)["participants"]

    assert presented_caller["value"]["capabilities"] == [
             %{
               "name" => "STT",
               "provider" => Vxpipe.Providers.Deepgram.Flux,
               "model" => "flux-general-en"
             }
           ]
  end

  test "does not fabricate ongoing duration or absent captured data" do
    call = %{call_summary() | state: :running, ended_at: nil, terminal_reason: nil}
    history = CallHistory.new([], %VariableSnapshotHistory{snapshots: [], latest: nil})

    response =
      CallInspectionPresenter.present(%CallInspectionResult{
        call: call,
        prepared_call: prepared_call(),
        history: history,
        usage: {:unavailable, :repository_unavailable}
      })

    assert response["call"]["duration_ms"] == nil
    assert length(response["participants"]) == 3
    refute Map.has_key?(response, "participant_configuration")
    assert response["variables"] == unavailable("not-captured")
    assert response["metrics"] == []
    assert response["metrics_availability"] == unavailable("not-loaded")
  end

  test "preserves captured empty tool arguments and an error response" do
    facts = [
      fact(:tool_call_started, 1, ~U[2026-09-16 09:00:01Z],
        tool_call_id: "tool-error",
        payload: %{"name" => "lookup", "arguments" => %{}}
      ),
      fact(:tool_call_failed, 2, ~U[2026-09-16 09:00:02Z],
        tool_call_id: "tool-error",
        payload: %{
          "name" => "lookup",
          "reason" => %{"message" => "upstream failed"},
          "response_status" => 503
        }
      )
    ]

    history = CallHistory.new(facts, %VariableSnapshotHistory{snapshots: [], latest: nil})

    response =
      CallInspectionPresenter.present(%CallInspectionResult{
        call: call_summary(),
        prepared_call: prepared_call(),
        history: history,
        usage: {:available, %UsageReport{amounts: [], totals: []}}
      })

    assert [tool_call] = response["timeline"]
    assert tool_call["value"]["status"] == "failed"
    assert tool_call["value"]["request"] == %{}
    assert tool_call["value"]["response"] == %{"message" => "upstream failed"}
    assert tool_call["value"]["response_status"] == 503
  end

  test "keeps usage amounts with distinct settlement provenance as distinct metrics" do
    report = usage_report()
    [provider_reported] = report.amounts

    locally_measured = %{
      provider_reported
      | provenance: :locally_measured,
        quantity: 41,
        observation_ids: ["usage-2"]
    }

    history =
      CallHistory.new(
        [
          fact(:usage_observed, 9, ~U[2026-09-16 09:00:09Z],
            id: "usage-2",
            payload: %{"attempt_id" => "model-attempt-1"}
          )
        ],
        %VariableSnapshotHistory{snapshots: [], latest: nil}
      )

    response =
      CallInspectionPresenter.present(%CallInspectionResult{
        call: call_summary(),
        prepared_call: prepared_call(),
        history: history,
        usage:
          {:available, %UsageReport{amounts: [provider_reported, locally_measured], totals: []}}
      })

    assert [first, second] = response["metrics"]
    refute first["id"] == second["id"]
    assert Enum.map([first, second], & &1["revision"]) |> Enum.sort() == [0, 9]
  end

  test "uses source sequence rather than timestamp to reduce a tool-call lifecycle" do
    facts = [
      fact(:tool_call_started, 10, ~U[2026-09-16 09:00:10Z],
        tool_call_id: "tool-out-of-order",
        payload: %{"name" => "lookup"}
      ),
      fact(:tool_call_completed, 11, ~U[2026-09-16 09:00:09Z],
        tool_call_id: "tool-out-of-order",
        payload: %{"name" => "lookup", "result" => %{"ok" => true}}
      )
    ]

    response =
      CallInspectionPresenter.present(%CallInspectionResult{
        call: call_summary(),
        prepared_call: prepared_call(),
        history: CallHistory.new(facts, %VariableSnapshotHistory{snapshots: [], latest: nil}),
        usage: {:available, %UsageReport{amounts: [], totals: []}}
      })

    assert [tool_call] = response["timeline"]
    assert tool_call["revision"] == 11
    assert tool_call["value"]["status"] == "completed"
    assert tool_call["value"]["response"] == %{"ok" => true}
  end

  test "uses the selected cumulative correction fact as the metric revision" do
    [amount] = usage_report().amounts

    correction = %{
      amount
      | quantity: 43,
        status: :correction,
        observation_ids: ["usage-correction"]
    }

    history =
      CallHistory.new(
        [
          fact(:usage_observed, 12, ~U[2026-09-16 09:00:12Z],
            id: "usage-correction",
            payload: %{"attempt_id" => "model-attempt-1"}
          )
        ],
        %VariableSnapshotHistory{snapshots: [], latest: nil}
      )

    response =
      CallInspectionPresenter.present(%CallInspectionResult{
        call: call_summary(),
        prepared_call: prepared_call(),
        history: history,
        usage: {:available, %UsageReport{amounts: [correction], totals: []}}
      })

    assert [metric] = response["metrics"]
    assert metric["revision"] == 12
    assert metric["value"]["value"] == 43
  end

  test "presents agent speech-to-speech selections with distinct transcript provenance" do
    assessment = result()
    plan = assessment.prepared_call.plan
    assistant = plan.participants["assistant"]

    sts_caps = %Capabilities{
      speech_to_speech: selection(:speech_to_speech, "morse", "morse"),
      output_speech_to_text: selection(:output_speech_to_text, "morse", "morse")
    }

    participants = Map.put(plan.participants, "assistant", %{assistant | capabilities: sts_caps})
    plan = %{plan | participants: participants}
    prepared_call = %{assessment.prepared_call | plan: plan}
    response = CallInspectionPresenter.present(%{assessment | prepared_call: prepared_call})

    assert [caller, presented_assistant, _support] = response["participants"]

    assert caller["value"]["capabilities"] == [
             %{"name" => "STT", "provider" => "morse", "model" => "morse"}
           ]

    assert presented_assistant["value"]["capabilities"] == [
             %{"name" => "STS", "provider" => "morse", "model" => "morse"},
             %{"name" => "Agent STT", "provider" => "morse", "model" => "morse"}
           ]
  end

  test "presents stored plans predating STS capabilities" do
    assessment = result()
    plan = assessment.prepared_call.plan

    old_caps = fn caps ->
      caps
      |> Map.delete(:speech_to_speech)
      |> Map.delete(:output_speech_to_text)
    end

    participants =
      Map.new(plan.participants, fn {key, participant} ->
        {key, %{participant | capabilities: old_caps.(participant.capabilities)}}
      end)

    old_plan = %{plan | participants: participants}

    assert {:ok, decoded} =
             old_plan
             |> :erlang.term_to_binary([:deterministic])
             |> Vxpipe.Persistence.ResolvedPlanCodec.decode()

    prepared_call = %{assessment.prepared_call | plan: decoded}
    response = CallInspectionPresenter.present(%{assessment | prepared_call: prepared_call})

    assert [caller, assistant, support] = response["participants"]

    assert caller["value"]["capabilities"] == [
             %{"name" => "STT", "provider" => "morse", "model" => "morse"}
           ]

    assert assistant["value"]["capabilities"] == [
             %{
               "name" => "LLM",
               "provider" => "google",
               "model" => "gemini-2.5-flash"
             },
             %{"name" => "TTS", "provider" => "morse", "model" => "morse"}
           ]

    assert support["value"]["capabilities"] == []
  end

  defp result do
    snapshot = variable_snapshot()

    history =
      CallHistory.new(history_facts(), %VariableSnapshotHistory{
        snapshots: [snapshot],
        latest: snapshot
      })

    %CallInspectionResult{
      call: call_summary(),
      prepared_call: prepared_call(),
      history: history,
      usage: {:available, usage_report()}
    }
  end

  defp call_summary do
    %CallSummary{
      id: "call-public-id",
      tenant_key: @tenant_key,
      call_spec_id: "call-spec-public-id",
      call_spec_revision: 3,
      state: :ended,
      created_at: ~U[2026-09-16 09:00:00Z],
      started_at: ~U[2026-09-16 09:00:01Z],
      ended_at: ~U[2026-09-16 09:01:31Z],
      terminal_reason: :completed,
      latest_variable_revision: 4
    }
  end

  defp history_facts do
    [
      fact(:accepted_input, 1, ~U[2025-12-31 23:59:59Z],
        participant_id: "caller-runtime",
        payload: %{"content" => "I need help", "modality" => "text"}
      ),
      fact(:participant_transcription_final, 2, ~U[2026-01-01 00:00:00Z],
        participant_id: "caller-runtime",
        payload: %{"text" => "I need help", "final" => true}
      ),
      fact(:tool_call_started, 3, ~U[2026-01-01 00:00:01Z],
        participant_id: "assistant-runtime",
        tool_call_id: "tool-1",
        payload: %{"name" => "lookup_order", "arguments" => %{}}
      ),
      fact(:tool_call_completed, 4, ~U[2026-01-01 00:00:02Z],
        participant_id: "assistant-runtime",
        tool_call_id: "tool-1",
        payload: %{
          "name" => "lookup_order",
          "result" => %{"ok" => true},
          "response_status" => 200
        }
      ),
      fact(:agent_output_generated, 5, ~U[2026-01-01 00:00:03Z],
        participant_id: "assistant-runtime",
        payload: %{"text" => "I found it", "will_be_spoken" => true}
      ),
      fact(:participant_left, 6, ~U[2026-01-01 00:00:04Z],
        participant_id: "caller-runtime",
        payload: %{"reason" => "completed"}
      )
    ]
  end

  defp fact(kind, sequence, occurred_at, options) do
    {:ok, fact} =
      CallFact.new(
        id: Keyword.get(options, :id, "fact-#{sequence}"),
        kind: kind,
        sequence: sequence,
        tenant_key: @tenant_key,
        call_id: "call-public-id",
        room_id: "room-public-id",
        incarnation_id: "incarnation-public-id",
        participant_id: Keyword.get(options, :participant_id),
        tool_call_id: Keyword.get(options, :tool_call_id),
        occurred_at: occurred_at,
        source_policy: %{"revision" => 1, "credential_name" => "private-value"},
        payload: Keyword.fetch!(options, :payload)
      )

    fact
  end

  defp variable_snapshot do
    {:ok, snapshot} =
      VariableSnapshot.new(
        id: "variables-4",
        kind: :update,
        tenant_key: @tenant_key,
        call_id: "call-public-id",
        room_id: "room-public-id",
        incarnation_id: "incarnation-public-id",
        global_revision: 4,
        sections: %{"order" => %{revision: 2, value: %{"status" => "ready"}}},
        source_policy: %{"revision" => 1},
        command_id: "command-4",
        participant_id: "assistant-runtime",
        activation_id: "activation-4",
        source_participant_id: "caller",
        correlation_id: "turn-4",
        tool_call_id: "tool-1",
        section: "order",
        section_revision: 2,
        occurred_at: ~U[2026-01-01 00:00:03Z]
      )

    snapshot
  end

  defp prepared_call do
    %PreparedCall{
      id: "call-public-id",
      tenant_key: @tenant_key,
      call_spec_id: "call-spec-public-id",
      call_spec_revision: 3,
      schema_version: "20260915.01",
      participant_routes: %{},
      entry_caller: "caller",
      entry_receiver: "assistant",
      initial_variables: %{},
      plan: resolved_plan(),
      plan_digest: <<0>>,
      state: :ended,
      room_id: "room-public-id",
      created_at: ~U[2026-09-16 09:00:00Z],
      started_at: ~U[2026-09-16 09:00:01Z],
      ended_at: ~U[2026-09-16 09:01:31Z],
      incarnation_id: "incarnation-public-id",
      terminal_reason: :completed
    }
  end

  defp resolved_plan do
    %ResolvedCallPlan{
      call_spec_id: "call-spec-public-id",
      call_spec_revision: 3,
      schema_version: "20260915.01",
      tenant_id: @tenant_key,
      actor_id: "actor-public-id",
      call_id: "call-public-id",
      room_id: "room-public-id",
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "assistant",
      opening_audio: nil,
      media_policy: nil,
      participants: %{
        "caller" =>
          participant(
            "caller",
            "caller-runtime",
            :human,
            web_connection(:start_call),
            %Capabilities{speech_to_text: selection(:speech_to_text, "morse", "morse")}
          ),
        "assistant" =>
          participant(
            "assistant",
            "assistant-runtime",
            :agent,
            nil,
            %Capabilities{
              model_inference:
                selection(
                  :model_inference,
                  "google",
                  "gemini-2.5-flash",
                  "private-credential-selector"
                ),
              text_to_speech: selection(:text_to_speech, "morse", "morse")
            },
            prompt: "Help the caller.",
            tools: %{
              "lookup_order" => %ToolBinding{
                name: "lookup_order",
                type: :host,
                conversation_mode: :blocking,
                action: nil,
                remote: nil,
                transfer: nil
              }
            },
            transfers: ["support"]
          ),
        "support" =>
          participant(
            "support",
            "support-runtime",
            :human,
            web_connection(:transfer),
            %Capabilities{}
          )
      },
      transfer_policy: nil,
      call_variables: nil,
      tool_visibility: nil,
      max_duration_ms: 120_000
    }
  end

  defp participant(call_spec_key, participant_id, kind, connection, capabilities, options \\ []) do
    %Participant{
      call_spec_key: call_spec_key,
      participant_id: participant_id,
      activation_id: nil,
      kind: kind,
      description: nil,
      connection: connection,
      transfer_notice: nil,
      prompt: Keyword.get(options, :prompt),
      first_message: nil,
      first_message_text: nil,
      capabilities: capabilities,
      while_present: nil,
      tools: Keyword.get(options, :tools, %{}),
      transfers: Keyword.get(options, :transfers, []),
      transfer_history: nil,
      variable_permissions: nil
    }
  end

  defp selection(kind, provider, model, credential_name \\ nil) do
    %CapabilitySelection{
      kind: kind,
      provider: provider,
      model: model,
      credential_name: credential_name,
      options: %{},
      provider_options: %{}
    }
  end

  defp web_connection(admission) do
    %ConnectionIntent{
      service: :web,
      mode: :receive,
      admission: admission,
      number: nil,
      number_from_variable: nil
    }
  end

  defp usage_report do
    amount = %EffectiveAmount{
      attempt_id: "model-attempt-1",
      capability: :model_inference,
      provider: %ProviderContext{name: "fixture"},
      attribution: %Attribution{participant_id: "assistant-runtime", turn_id: "turn-1"},
      component: "output_tokens",
      unit: :tokens,
      quantity: 42,
      mode: :cumulative,
      status: :final,
      provenance: :provider_reported,
      observation_ids: ["usage-1"],
      included_in: nil
    }

    %UsageReport{amounts: [amount], totals: []}
  end

  defp unavailable(reason), do: %{"state" => "unavailable", "reason" => reason}
end
