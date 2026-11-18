defmodule Vxpipe.Calls.CallSpecErrorsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Error
  alias Vxpipe.Calls.CallSpecErrors

  test "unsupported model errors preserve their location with safe actionable guidance" do
    path = ["participants", "receptionist", "capabilities", "model_inference"]
    details = %{"path" => path, "reason" => "private provider details"}
    error = Error.new(:unsupported_agent_protocol, "private message", details: details)

    for input <- [error, Error.to_public(error)] do
      assert [projected] = CallSpecErrors.validation_errors([input])
      assert projected.path == path ++ ["model"]
      assert projected.code == "unsupported_call_plan"

      assert projected.reason ==
               "This model is not supported for agent replies yet. Choose a supported model in Models."

      refute inspect(projected) =~ "private"
    end
  end

  test "unsupported idle tool errors point to tools" do
    error =
      Error.new(:unsupported_agent_protocol, "private",
        details: %{
          "path" => ["participants", "assistant", "tools"]
        }
      )

    assert {422, projected} = CallSpecErrors.response(error)
    assert projected.path == ["participants", "assistant", "tools"]
    assert projected.reason =~ "Idle"
  end
end
