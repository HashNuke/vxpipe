defmodule Vxpipe.Gateway.Telephony.SourceGate do
  @moduledoc false

  # MediaSession-side counterpart of `SourceEpoch`. It records the expected
  # telephony source epoch: `nil` before any cutover, `{:held, old_epoch}` while
  # a source hold is in force, and `{:active, epoch}` after an arm. Admitted
  # media must carry the exact active epoch; stale or unqualified media is
  # acknowledged and dropped so the socket stays healthy. This gate is separate
  # from the transfer `handoff_gate`. See `docs/sts-activity-provenance.md`.

  @type t :: nil | {:held, reference() | nil} | {:active, reference()}

  @spec new() :: nil
  def new, do: nil

  @spec hold(t()) :: t()
  def hold(nil), do: {:held, nil}
  def hold({:held, epoch}), do: {:held, epoch}
  def hold({:active, epoch}), do: {:held, epoch}

  @spec arm(t(), reference()) :: t()
  def arm(_gate, epoch) when is_reference(epoch), do: {:active, epoch}

  @spec held?(t()) :: boolean()
  def held?({:held, _epoch}), do: true
  def held?(_gate), do: false

  @spec admitted?(t(), reference() | nil) :: boolean()
  def admitted?(nil, _epoch), do: true
  def admitted?({:held, _held_epoch}, _epoch), do: false
  def admitted?({:active, epoch}, epoch), do: true
  def admitted?({:active, _epoch}, _actual), do: false
end
