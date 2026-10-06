defmodule Vxpipe.Console.LiveTelephonyTransferModelTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Message, ModelRequest}
  alias Vxpipe.Console.Test.LiveTelephonyTransferModel

  test "destination speech waits for the bridge gate before emitting its marker" do
    observer = self()
    once = start_supervised!({Agent, fn -> false end})

    gate =
      start_supervised!(
        {Agent, fn -> %{open?: false, waiting: [], observer: observer} end},
        id: :destination_gate
      )

    assert {:ok, model} =
             LiveTelephonyTransferModel.new(
               model: "test:telephony-destination",
               once: once,
               destination_gate: gate
             )

    request = ModelRequest.new([Message.user("Delta.")], [], [], %{})

    start_supervised!(
      {Task,
       fn ->
         result =
           LiveTelephonyTransferModel.stream(model, request, fn text ->
             send(observer, {:spoken, text})
             :ok
           end)

         send(observer, {:destination_result, result})
       end}
    )

    assert_receive {:live_destination_waiting, _reference}
    refute_received {:spoken, _}
    assert :ok = LiveTelephonyTransferModel.open_destination(gate)
    assert_receive {:spoken, "Bravo."}
    assert_receive {:destination_result, {:ok, response}}
    assert response.text == "Bravo."

    assert {:ok, following} =
             LiveTelephonyTransferModel.stream(model, request, fn text ->
               assert text == "Bravo."
               :ok
             end)

    assert following.text == "Bravo."
  end

  test "reception requests one protected destination transfer across all turns" do
    once = start_supervised!({Agent, fn -> false end})

    assert {:ok, model} =
             LiveTelephonyTransferModel.new(model: "test:telephony-reception", once: once)

    assert :ready = LiveTelephonyTransferModel.readiness(model)
    request = ModelRequest.new([Message.user("Alpha.")], [], [], %{})

    assert {:ok, response} =
             LiveTelephonyTransferModel.stream(model, request, fn _ ->
               flunk("unexpected speech")
             end)

    assert [tool] = response.tool_calls
    assert tool.name == "transfer"
    assert tool.arguments == %{"destination" => "support", "reason" => "Delta."}

    assert {:ok, following} =
             LiveTelephonyTransferModel.stream(model, request, fn text ->
               assert text == "Charlie."
               :ok
             end)

    assert following.tool_calls == []
    assert following.text == "Charlie."
  end

  test "caller and destination emit opposing acoustic markers without tools" do
    once = start_supervised!({Agent, fn -> false end})
    request = ModelRequest.new([Message.user("Charlie.")], [], [], %{})

    for {role, phrase} <- [{"caller", "Alpha."}, {"destination", "Bravo."}] do
      assert {:ok, model} =
               LiveTelephonyTransferModel.new(model: "test:telephony-#{role}", once: once)

      observer = self()

      assert {:ok, response} =
               LiveTelephonyTransferModel.stream(model, request, fn text ->
                 send(observer, {:spoken, text})
                 :ok
               end)

      assert_receive {:spoken, ^phrase}
      assert response.text == phrase
      assert response.tool_calls == []
    end
  end
end
