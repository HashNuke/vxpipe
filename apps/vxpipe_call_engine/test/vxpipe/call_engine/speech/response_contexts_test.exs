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

  test "retire removes accepted contexts, ignores unknown, and keeps the staged one" do
    first = make_ref()
    second = make_ref()
    unknown = make_ref()
    command1 = make_ref()
    command2 = make_ref()

    owner = Contexts.new()
    {:ok, owner} = Contexts.stage(owner, first, command1)
    owner = Contexts.accept(owner, command1)
    {:ok, owner} = Contexts.stage(owner, second, command2)

    owner = Contexts.retire(owner, [first, unknown])

    assert Contexts.status(owner, first) == :retired
    assert Contexts.status(owner, unknown) == :unknown
    assert Contexts.status(owner, second) == :staged
  end

  test "the retired tombstone window is bounded and evicts the oldest" do
    {owner, contexts} =
      Enum.reduce(1..20, {Contexts.new(), []}, fn _n, {owner, contexts} ->
        context = make_ref()
        command = make_ref()
        {:ok, owner} = Contexts.stage(owner, context, command)
        owner = Contexts.accept(owner, command)
        owner = Contexts.retire(owner, [context])
        {owner, [context | contexts]}
      end)

    assert length(owner.retired) == 16
    assert Contexts.status(owner, hd(contexts)) == :retired
    assert Contexts.status(owner, List.last(contexts)) == :unknown
  end

  test "retirement frees capacity at the context bound" do
    owner = Contexts.new()

    owner =
      Enum.reduce(1..16, owner, fn _n, owner ->
        context = make_ref()
        command = make_ref()
        {:ok, owner} = Contexts.stage(owner, context, command)
        Contexts.accept(owner, command)
      end)

    assert {:error, :busy} = Contexts.stage(owner, make_ref(), make_ref())

    retired = owner.contexts |> Map.keys() |> Enum.take(4)
    owner = Contexts.retire(owner, retired)

    assert {:ok, owner} = Contexts.stage(owner, make_ref(), make_ref())
    assert map_size(owner.contexts) <= 16
  end
end
