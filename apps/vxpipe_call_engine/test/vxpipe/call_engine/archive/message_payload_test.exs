defmodule Vxpipe.CallEngine.Archive.MessagePayloadTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.{MessagePayload, Policy}

  test "generated output has versioned dialogue metadata alongside media facts" do
    event =
      struct!(Vxpipe.CallEngine.Event.TextOutput,
        id: "output",
        sequence: 1,
        tenant_id: "tenant",
        room_id: "room",
        incarnation_id: "incarnation",
        participant_id: "agent",
        source_participant_id: "human",
        connection_id: "connection",
        command_id: "command",
        correlation_id: "correlation",
        text: "okay",
        agent_mode: :listener,
        aggregated_by: :sentence,
        will_be_spoken: true,
        occurred_at: DateTime.utc_now()
      )

    assert {:agent_output_generated, attributes} =
             Vxpipe.CallEngine.Archive.EventProjection.project(event)

    payload = Keyword.fetch!(attributes, :payload)

    assert payload == %{
             "content_format" => "structured_agent_message_v1",
             "content" => %{
               "type" => "participant_message",
               "participant_id" => "agent",
               "message" => "okay",
               "agent_mode" => "listener"
             },
             "aggregated_by" => :sentence,
             "will_be_spoken" => true
           }
  end

  test "distinguishes versioned content from literal legacy JSON and checks trusted identity" do
    content = %{
      "type" => "participant_message",
      "participant_id" => "human-1",
      "agent_mode" => "speaker",
      "message" => "quoted \"雪\""
    }

    payload = %{"content_format" => "structured_agent_message_v1", "content" => content}

    assert MessagePayload.project(:accepted_input, payload, "human-1") ==
             %{text: "quoted \"雪\"", agent_mode: "speaker"}

    assert MessagePayload.project(
             :accepted_input,
             %{payload | "content" => JSON.encode!(content)},
             "human-1"
           ) ==
             MessagePayload.project(:accepted_input, payload, "human-1")

    assert MessagePayload.project(:accepted_input, payload, "other") == nil

    assert MessagePayload.project(
             :accepted_input,
             %{payload | "content_format" => "future"},
             "human-1"
           ) == nil

    literal = JSON.encode!(content)

    assert MessagePayload.project(:accepted_input, %{"content" => literal}, "human-1") == %{
             text: literal
           }

    assert MessagePayload.project(:agent_output_generated, %{"text" => "legacy"}, "agent") == %{
             text: "legacy"
           }
  end

  test "only dialogue becomes speech; listener text has cue purpose and silence has no bubble" do
    for message <- [nil, "", " "] do
      payload =
        MessagePayload.wrap(%{
          "type" => "participant_message",
          "participant_id" => "agent",
          "agent_mode" => "listener",
          "message" => message
        })

      assert MessagePayload.project(:agent_output_generated, payload, "agent") == nil
    end

    payload =
      MessagePayload.wrap(%{
        "type" => "participant_message",
        "participant_id" => "agent",
        "agent_mode" => "listener",
        "message" => "okay"
      })

    assert MessagePayload.project(:agent_output_generated, payload, "agent") ==
             %{text: "okay", agent_mode: "listener", output_purpose: "backchannel"}

    for type <- ["platform_event", "conversation_summary", "tool_result"] do
      assert MessagePayload.project(
               :accepted_input,
               MessagePayload.wrap(%{
                 "type" => type,
                 "participant_id" => "human",
                 "message" => "not speech"
               }),
               "human"
             ) == nil
    end

    assert MessagePayload.project(:tool_call_completed, payload, "agent") == nil
  end

  test "transcript-disabled policy removes structured and copied nested text before archiving" do
    payload = %{
      "content_format" => "structured_agent_message_v1",
      "content" => %{"message" => "private"},
      "metadata" => %{
        "items" => [
          %{
            "message" => "private",
            "summary" => "private",
            "raw_response" => "private",
            "id" => "kept"
          }
        ]
      }
    }

    assert Policy.filter_payload(:accepted_input, payload, %{"save_transcripts" => false}) ==
             %{
               "content_format" => "structured_agent_message_v1",
               "metadata" => %{"items" => [%{"id" => "kept"}]}
             }

    assert Policy.filter_payload(:accepted_input, payload, %{"save_transcripts" => true}) ==
             payload
  end

  test "bounds decoded content as well as encoded JSON, including escaped text" do
    for text <- [
          String.duplicate("x", 16 * 1_024 * 1_024 + 1),
          String.duplicate("\n", 8 * 1_024 * 1_024)
        ] do
      content = %{
        "type" => "participant_message",
        "participant_id" => "agent",
        "agent_mode" => "speaker",
        "message" => text
      }

      payload = MessagePayload.wrap(content)

      assert is_nil(
               MessagePayload.project(
                 :agent_output_generated,
                 %{payload | "content" => JSON.encode!(content)},
                 "agent"
               )
             )

      assert is_nil(MessagePayload.project(:agent_output_generated, payload, "agent"))
    end
  end
end
