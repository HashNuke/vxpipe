defmodule Vxpipe.CallEngine.Diagnostics.InferenceTap do
  @moduledoc "Prospective observation of operational Silero results; never runs or cancels inference."
  alias Vxpipe.CallEngine.Diagnostics.CaptureHandoff
  alias Vxpipe.CallEngine.Speech.Silero
  @enforce_keys [:handoff, :armed?]
  @derive {Inspect, only: [:armed?]}
  defstruct @enforce_keys

  def attach(previous, handoff, epoch, stream, in_flight?, clean_input?) do
    cond do
      not CaptureHandoff.current?(handoff) ->
        previous

      previous != nil and previous.handoff.token == handoff.token ->
        previous

      true ->
        if previous, do: CaptureHandoff.close(previous.handoff)

        armed? =
          not in_flight? and clean_input? and
            match?(%Silero{samples: 0, pending: ""}, stream)

        tap = %__MODULE__{handoff: handoff, armed?: armed?}
        if not armed?, do: notice(tap, epoch, :partial_start)
        tap
    end
  end

  def begin(%__MODULE__{armed?: true, handoff: handoff}, epoch, %Silero{} = stream) do
    if CaptureHandoff.current?(handoff), do: {handoff, epoch, stream.samples}
  end

  def begin(_tap, _epoch, _stream), do: nil

  def result(nil, _probabilities), do: :ok
  def result(_context, []), do: :ok

  def result({handoff, epoch, first_sample}, probabilities) do
    _ =
      CaptureHandoff.offer(
        handoff,
        {:probabilities, epoch, first_sample, probabilities, System.monotonic_time(:microsecond)}
      )

    :ok
  end

  def reset(nil, _epoch, _clean?), do: nil

  def reset(tap, epoch, clean?) do
    notice(tap, epoch, :provider_turn_settled)
    if not clean?, do: notice(tap, epoch, :partial_start)
    %{tap | armed?: clean?}
  end

  def failed(nil), do: :ok

  def failed({handoff, epoch, _sample}),
    do: notice(%__MODULE__{handoff: handoff, armed?: false}, epoch, :inference_failed)

  defp notice(tap, epoch, reason) do
    _ =
      CaptureHandoff.offer(
        tap.handoff,
        {:reset, epoch, reason, System.monotonic_time(:microsecond)}
      )

    :ok
  end
end
