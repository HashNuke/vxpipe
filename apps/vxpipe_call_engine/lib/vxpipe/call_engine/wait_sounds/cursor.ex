defmodule Vxpipe.CallEngine.WaitSounds.Cursor do
  @moduledoc false

  @frame_bytes 1_920

  @spec next(binary(), non_neg_integer(), boolean()) :: :complete | {binary(), non_neg_integer()}
  def next(payload, offset, false) when offset >= byte_size(payload), do: :complete

  def next(payload, offset, false) do
    size = min(@frame_bytes, byte_size(payload) - offset)
    {binary_part(payload, offset, size), offset + size}
  end

  def next(payload, offset, true) do
    take(payload, rem(offset, byte_size(payload)), @frame_bytes, [])
  end

  defp take(_payload, offset, 0, parts),
    do: {parts |> Enum.reverse() |> IO.iodata_to_binary(), offset}

  defp take(payload, offset, remaining, parts) do
    size = min(remaining, byte_size(payload) - offset)
    part = binary_part(payload, offset, size)
    take(payload, rem(offset + size, byte_size(payload)), remaining - size, [part | parts])
  end
end
