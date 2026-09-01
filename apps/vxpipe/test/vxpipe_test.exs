defmodule VxpipeTest do
  use ExUnit.Case

  test "starts the shared room runtime" do
    assert Process.whereis(Vxpipe.RoomRegistry)
    assert Process.whereis(Vxpipe.SubscriberTaskSupervisor)
    assert Process.whereis(Vxpipe.RoomsSupervisor)
  end
end
