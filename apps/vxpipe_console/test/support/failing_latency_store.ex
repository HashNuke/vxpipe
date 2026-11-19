defmodule Vxpipe.Console.Test.FailingLatencyStore do
  @moduledoc false

  def put_run(context, _run), do: attempt(context)
  def put_turn(context, _tenant, _call, _incarnation, _turn), do: attempt(context)

  defp attempt({observer, failure}) do
    send(observer, {:diagnostic_storage_attempt, failure, self()})

    case failure do
      :error -> {:error, :synthetic_storage_failure}
      :blocked -> blocked()
    end
  end

  defp blocked do
    receive do
      {:still_blocked, observer, reference} ->
        send(observer, {:storage_still_blocked, self(), reference})
        blocked()
    end
  end
end
