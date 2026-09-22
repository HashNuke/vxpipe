defmodule Vxpipe.CallEngine.Speech.ResponseContextsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Speech.ResponseContexts, as: Contexts

  test "exact command settles staging and stale results cannot settle another reservation" do
    context = make_ref()
    command = make_ref()
    {:ok, staged} = Contexts.stage(Contexts.new(), context, command)
    assert Contexts.status(staged, context) == :staged
    assert Contexts.accept(staged, make_ref()) == staged
    assert Contexts.rollback(staged, make_ref()) == staged
    assert {:error, :busy} = Contexts.stage(staged, context, make_ref())
    assert Contexts.status(Contexts.rollback(staged, command), context) == :unknown
    accepted = Contexts.accept(staged, command)
    assert Contexts.status(accepted, context) == :accepted
    next = make_ref()
    {:ok, reused} = Contexts.stage(accepted, context, next)
    assert Contexts.status(reused, context) == :accepted
    assert Contexts.rollback(reused, next) == accepted
  end

  test "rollback frees first-use capacity without tombstones" do
    empty = Contexts.new()

    for _ <- 1..32 do
      command = make_ref()
      {:ok, staged} = Contexts.stage(empty, make_ref(), command)
      assert Contexts.rollback(staged, command) == empty
    end

    assert {:error, :invalid_response_context} = Contexts.stage(empty, nil, make_ref())
  end
end
