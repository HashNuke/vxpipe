defmodule Vxpipe.Calls.TestControlledLatencyRepository do
  def put_turn(owner, tenant, call, incarnation, turn) do
    send(owner, {:diagnostic_turn_write, self(), {tenant, call, incarnation}, turn})

    receive do
      {:finish, result} -> result
    end
  end

  def put_run(owner, run) do
    send(owner, {:diagnostic_write, self(), run})

    receive do
      {:finish, result} -> result
    end
  end
end
