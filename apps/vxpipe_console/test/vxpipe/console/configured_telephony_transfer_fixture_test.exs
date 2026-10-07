defmodule Vxpipe.Console.ConfiguredTelephonyTransferFixtureTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec
  alias Vxpipe.Console.Test.ConfiguredTelephonyFixture

  test "transfer publication publishes three distinct sources before any dial" do
    fixture = %ConfiguredTelephonyFixture{
      settings: %{numbers: %{"twilio" => "+15550001001", "telnyx" => "+15550001002"}}
    }

    publication =
      ConfiguredTelephonyFixture.publish_transfer(fixture, fn ^fixture, source ->
        id = make_ref()
        send(self(), {:published_transfer_source, id, source})
        %{call_spec_id: id, source: source}
      end)

    assert MapSet.new(Map.keys(publication)) == MapSet.new([:caller, :reception, :destination])

    for {_role, published} <- publication do
      id = published.call_spec_id
      source = published.source
      assert_receive {:published_transfer_source, ^id, ^source}
    end

    assert publication.caller.source.outgoing_call.callee == "human"
    assert publication.reception.source.incoming_call.caller == "human"
    assert publication.destination.source.incoming_call.caller == "human"
    refute_received {:published_transfer_source, _, _}
  end

  test "the GPT-Live pair dials with a speech-to-speech handler and a carrier receiver" do
    fixture = %ConfiguredTelephonyFixture{
      settings: %{numbers: %{"twilio" => "+15550001001", "telnyx" => "+15550001002"}}
    }

    sources = ConfiguredTelephonyFixture.sts_sources(fixture, "twilio", "telnyx")

    for {name, source} <- sources do
      assert {:ok, _spec} = CallSpec.new(source, resource_id: "live-sts-#{name}", revision: 1)
    end

    assistant = sources.outgoing.participants["assistant"]

    assert assistant.capabilities.speech_to_speech == %{
             provider: "openai",
             model: "gpt-live-1",
             credential_name: "live-telephony",
             options: %{backend_model: "gpt-6-luna"}
           }

    refute Map.has_key?(assistant.capabilities, :model_inference)
    refute Map.has_key?(assistant.capabilities, :text_to_speech)
    assert assistant.first_message == %{mode: "fixed", text: "Alpha."}
    assert assistant.prompt =~ "Charlie"
    assert sources.outgoing.outgoing_call.callee == "human"
    refute Map.has_key?(sources.outgoing.participants["human"].connection, :number)
    assert sources.incoming.incoming_call.caller == "human"
    assert sources.incoming.participants["assistant"].first_message.text == "Bravo."
  end

  test "the GPT-Live barge-in pair puts a second GPT-Live on the receiving number" do
    fixture = %ConfiguredTelephonyFixture{
      settings: %{numbers: %{"twilio" => "+15550001001", "telnyx" => "+15550001002"}}
    }

    sources = ConfiguredTelephonyFixture.sts_sources(fixture, "twilio", "telnyx", :barge_in)

    for {name, source} <- sources do
      assert {:ok, _spec} = CallSpec.new(source, resource_id: "live-barge-#{name}", revision: 1)
    end

    model = sources.outgoing.participants["assistant"]
    assert model.capabilities.speech_to_speech.provider == "openai"
    assert model.prompt =~ "count slowly from one to thirty"
    assert model.prompt =~ "say only: I have stopped."

    receiver = sources.incoming.participants["assistant"]
    assert receiver.capabilities.speech_to_speech.provider == "openai"
    assert receiver.first_message == %{mode: "wait_for_input"}
    assert receiver.prompt =~ "say: Stop counting now"
  end

  test "the GPT-Live long-session pair trades Ping and Pong within a raised call limit" do
    fixture = %ConfiguredTelephonyFixture{
      settings: %{numbers: %{"twilio" => "+15550001001", "telnyx" => "+15550001002"}}
    }

    sources =
      ConfiguredTelephonyFixture.sts_sources(
        fixture,
        "twilio",
        "telnyx",
        {:long_session, 600_000}
      )

    for {name, source} <- sources do
      assert {:ok, _spec} = CallSpec.new(source, resource_id: "live-long-#{name}", revision: 1)
      assert source.limits.max_duration_ms == 780_000
    end

    model = sources.outgoing.participants["assistant"]
    assert model.first_message == %{mode: "fixed", text: "Ping."}
    assert model.prompt =~ "Every time the other party says Pong, reply with exactly: Ping."
    assert sources.incoming.participants["assistant"].prompt =~ "reply with exactly: Pong."
  end

  test "the three-party carrier fixture validates portable receive and private-transfer contracts" do
    fixture = %ConfiguredTelephonyFixture{
      settings: %{numbers: %{"twilio" => "+15550001001", "telnyx" => "+15550001002"}}
    }

    sources = ConfiguredTelephonyFixture.transfer_sources(fixture)

    for {name, source} <- sources do
      assert {:ok, _spec} = CallSpec.new(source, resource_id: "live-#{name}", revision: 1)
      assert source.wait_sounds == nil
      assert source.media_policy == %{save_transcripts: true, record_audio: false}
      assert source.limits.max_duration_ms == 90_000

      assert source.participants["assistant"].capabilities.model_inference == %{
               provider: "fixture",
               model: "test:telephony-#{name}"
             }
    end

    assert sources.caller.outgoing_call.callee == "human"

    assert sources.caller.participants["human"].connection == %{
             service: "live-telnyx",
             mode: "dial",
             number: "+15550001001"
           }

    reception = sources.reception
    assert reception.incoming_call == %{caller: "human", handled_by: "assistant"}
    assert reception.participants["human"].connection.service == "live-twilio"
    assert reception.participants["assistant"].transfers == ["support"]
    assert reception.transfer_policy.attempt_timeout_ms == 30_000
    support = reception.participants["support"]
    assert support.type == "human"

    assert support.connection == %{
             service: "live-twilio",
             mode: "dial",
             number: "+15550001002"
           }

    assert support.transfer_notice == "Private destination check. The transfer code is Delta."
    assert support.capabilities.speech_to_text.provider == "deepgram"
    refute Map.has_key?(support.connection, :number_from_variable)
    assert sources.destination.participants["human"].connection.service == "live-telnyx"
    assert sources.destination.incoming_call.caller == "human"
  end
end
