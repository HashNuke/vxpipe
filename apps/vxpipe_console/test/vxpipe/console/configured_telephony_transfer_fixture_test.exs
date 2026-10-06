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
