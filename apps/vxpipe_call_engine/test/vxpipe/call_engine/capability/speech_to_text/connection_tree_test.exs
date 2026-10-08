defmodule Vxpipe.CallEngine.Capability.SpeechToText.ConnectionTreeTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Capability.SpeechToText.ConnectionTree

  test "a tree lost during provider startup reports unavailable instead of exiting the caller" do
    tree =
      start_supervised!(%{
        id: :connection_tree,
        start: {Supervisor, :start_link, [[], [strategy: :one_for_one, name: __MODULE__.Tree]]}
      })

    monitor = Process.monitor(tree)
    stop_supervised!(:connection_tree)
    assert_receive {:DOWN, ^monitor, :process, ^tree, :shutdown}
    assert {:error, :unavailable} = ConnectionTree.children(tree)
  end

  test "a tree without its capability and ingress reports unavailable" do
    tree =
      start_supervised!(%{
        id: :connection_tree,
        start: {Supervisor, :start_link, [[], [strategy: :one_for_one, name: __MODULE__.Tree]]}
      })

    assert {:error, :unavailable} = ConnectionTree.children(tree)
  end
end
