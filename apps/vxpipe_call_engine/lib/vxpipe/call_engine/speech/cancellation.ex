defmodule Vxpipe.CallEngine.Speech.Cancellation do
  @moduledoc "An exact output fence with one deadline covering sink interruption and cancellation."
  @enforce_keys [:session, :request_ref, :consumer, :ref, :deadline]
  @derive {Inspect, only: [:request_ref, :ref, :deadline]}
  defstruct @enforce_keys
  @type t :: %__MODULE__{}

  def evaluate(command, ticket, played_ms, caller, consumer, allocation, current, last, now) do
    cond do
      caller != consumer or ticket.consumer != caller or ticket.session != allocation ->
        {:reply, {:error, :not_owner}}

      last && last.ticket == ticket ->
        {:reply, result(last, played_ms)}

      is_nil(current) or current.ticket != ticket ->
        {:reply, {:error, :stale_cancellation}}

      ticket.deadline <= now ->
        {:fail, :command_timeout}

      current.accepted? ->
        {:reply, result(current, played_ms)}

      not is_nil(current.pending) ->
        {:reply, {:error, :busy}}

      not is_integer(played_ms) or played_ms < 0 ->
        {:reply, {:error, :invalid_playback}}

      command.deadline <= now or :atomics.compare_exchange(command.token, 1, 0, 1) != :ok ->
        {:reply, {:error, :command_timeout}}

      true ->
        {:continue, %{command | deadline: min(command.deadline, ticket.deadline)}}
    end
  end

  def result(%{playback: playback}, played_ms) do
    if playback.request_played_ms == played_ms,
      do: {:ok, playback},
      else: {:error, :conflicting_playback}
  end
end
