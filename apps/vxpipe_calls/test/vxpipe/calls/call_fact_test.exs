defmodule Vxpipe.Calls.CallFactTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.CallFact

  test "decodes only supported persisted kind names" do
    assert {:ok, :participant_joined} = CallFact.decode_kind("participant_joined")
    assert {:ok, :usage_observed} = CallFact.decode_kind("usage_observed")
    assert :error = CallFact.decode_kind("future_untrusted_kind")
    assert :error = CallFact.decode_kind(:participant_joined)
  end
end
