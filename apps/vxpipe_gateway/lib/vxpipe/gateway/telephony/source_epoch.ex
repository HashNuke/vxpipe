defmodule Vxpipe.Gateway.Telephony.SourceEpoch do
  @moduledoc false

  # Telephony source-admission epoch for the WebSock media path. The socket
  # stamps each decoded media event with the current epoch before asynchronous
  # `SocketDispatch`. A hold rotates that epoch in mailbox order, so raw frames
  # already queued keep the old stamp, and an arm adopts the room-chosen active
  # epoch. The MediaSession compares the stamp with its expected epoch and drops
  # stale media. See `docs/sts-activity-provenance.md`.

  @type gate :: %{
          held?: boolean(),
          token: reference() | nil,
          old_epoch: reference() | nil
        }

  @spec new() :: nil
  def new, do: nil

  @spec held?(gate() | nil) :: boolean()
  def held?(%{held?: held?}), do: held?
  def held?(_gate), do: false

  @spec hold(reference(), gate() | nil, map()) ::
          {:ok, map(), reference(), gate()} | {:error, atom()}
  def hold(epoch, gate, %{token: token, deadline_ms: deadline})
      when is_reference(epoch) and is_reference(token) and is_integer(deadline) do
    cond do
      held?(gate) ->
        {:error, :stale_source}

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :deadline_elapsed}

      true ->
        held_epoch = make_ref()
        receipt = %{socket: self(), old_epoch: epoch, held_epoch: held_epoch}
        {:ok, receipt, held_epoch, %{held?: true, token: token, old_epoch: epoch}}
    end
  end

  def hold(_epoch, _gate, _scope), do: {:error, :stale_source}

  @spec arm(reference(), gate() | nil, map()) ::
          {:ok, reference(), gate()} | {:error, atom()}
  def arm(epoch, gate, %{token: token, active_epoch: active_epoch, deadline_ms: deadline})
      when is_reference(epoch) and is_reference(token) and is_reference(active_epoch) and
             is_integer(deadline) do
    cond do
      not held?(gate) ->
        {:error, :stale_source}

      gate.token != token ->
        {:error, :stale_source}

      active_epoch == epoch or active_epoch == gate.old_epoch ->
        {:error, :stale_source}

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :deadline_elapsed}

      true ->
        {:ok, active_epoch, %{held?: false, token: nil, old_epoch: nil}}
    end
  end

  def arm(_epoch, _gate, _scope), do: {:error, :stale_source}

  @spec reply(map(), atom(), term()) :: :ok
  def reply(scope, tag, result) do
    case Map.get(scope, :reply_to) do
      pid when is_pid(pid) -> send(pid, {tag, Map.get(scope, :token), result})
      _ -> :ok
    end
  end
end
