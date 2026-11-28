defmodule Vxpipe.CallEngine.Speech.Silero.Batch do
  @moduledoc false
  alias Vxpipe.CallEngine.Speech.Silero.Model

  # 64 context samples and two 128-element recurrent layers, little-endian f32.
  @initial_state :binary.copy(<<0>>, (64 + 2 * 128) * 4)
  def initial_state, do: @initial_state

  def run(%Model{resource: %Ortex.Model{reference: reference}}, rows) do
    {:ok, Ortex.Native.silero_batch(reference, rows)}
  rescue
    _ -> {:error, :classification_failed}
  end
end
