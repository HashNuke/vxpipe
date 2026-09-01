defmodule Vxpipe.ServerTest do
  use ExUnit.Case

  test "supervises the standalone HTTP server" do
    assert Process.whereis(Vxpipe.Server.Supervisor)

    assert [{_, pid, :supervisor, [Bandit]}] =
             Supervisor.which_children(Vxpipe.Server.Supervisor)

    assert is_pid(pid)
  end
end
