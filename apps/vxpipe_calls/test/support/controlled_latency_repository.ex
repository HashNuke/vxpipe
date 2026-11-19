defmodule Vxpipe.Calls.TestControlledLatencyRepository do
  def put_run(owner, run) do
    send(owner, {:diagnostic_write, self(), run})

    receive do
      {:finish, result} -> result
    end
  end
end
