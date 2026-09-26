defmodule Vxpipe.CallEngine.Speech.ResponseContextsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.ResponseContexts

  test "retire removes accepted contexts, ignores unknown, and keeps the staged one" do
    first = make_ref()
    second = make_ref()
    unknown = make_ref()
    command1 = make_ref()
    command2 = make_ref()

    owner = ResponseContexts.new()
    {:ok, owner} = ResponseContexts.stage(owner, first, command1)
    owner = ResponseContexts.accept(owner, command1)
    {:ok, owner} = ResponseContexts.stage(owner, second, command2)

    owner = ResponseContexts.retire(owner, [first, unknown])

    assert ResponseContexts.status(owner, first) == :unknown
    assert ResponseContexts.status(owner, unknown) == :unknown
    assert ResponseContexts.status(owner, second) == :staged
  end

  test "retirement frees capacity at the context bound" do
    owner = ResponseContexts.new()

    owner =
      Enum.reduce(1..16, owner, fn _n, owner ->
        context = make_ref()
        command = make_ref()
        {:ok, owner} = ResponseContexts.stage(owner, context, command)
        ResponseContexts.accept(owner, command)
      end)

    assert {:error, :busy} = ResponseContexts.stage(owner, make_ref(), make_ref())

    retired = owner.contexts |> Map.keys() |> Enum.take(4)
    owner = ResponseContexts.retire(owner, retired)

    assert {:ok, owner} = ResponseContexts.stage(owner, make_ref(), make_ref())
    assert map_size(owner.contexts) <= 16
  end
end
