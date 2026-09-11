defmodule Vxpipe.Gateway.Sideband.CodecTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Sideband.Codec

  test "decodes destination acceptance for one explicit transfer attempt" do
    payload =
      JSON.encode!(%{
        "id" => "accept-1",
        "type" => "transfer.accept",
        "data" => %{"attempt_id" => "xfer-1"}
      })

    assert {:command, {:accept, %{id: "accept-1", attempt_id: "xfer-1"}}} =
             Codec.handle(payload)
  end

  test "rejects malformed acceptance without reflecting private input" do
    payload =
      JSON.encode!(%{
        "id" => "accept-invalid",
        "type" => "transfer.accept",
        "data" => %{"attempt_id" => "not valid", "private" => "do-not-reflect"}
      })

    assert {:reply, reply} = Codec.handle(payload)

    assert %{
             "id" => "accept-invalid",
             "type" => "error",
             "data" => %{"message" => "The transfer control could not be accepted."}
           } = JSON.decode!(reply)

    refute reply =~ "do-not-reflect"
    refute reply =~ "not valid"
  end

  test "encodes only bounded transfer preparation and activation state" do
    assert {:ok, preparation} = Codec.encode_preparation("xfer-1", "part-support")

    assert %{
             "id" => "xfer-1",
             "type" => "transfer.preparation",
             "data" => %{
               "attempt_id" => "xfer-1",
               "participant_id" => "part-support"
             }
           } = JSON.decode!(preparation)

    assert {:ok, active} = Codec.encode_active("xfer-1")

    assert %{
             "id" => "xfer-1",
             "type" => "transfer.active",
             "data" => %{"attempt_id" => "xfer-1"}
           } = JSON.decode!(active)
  end

  test "ignores unrelated and oversized messages" do
    assert :ignore = Codec.handle(JSON.encode!(%{"id" => "x", "type" => "other", "data" => %{}}))
    assert :ignore = Codec.handle(String.duplicate("x", 4_097))
  end
end
