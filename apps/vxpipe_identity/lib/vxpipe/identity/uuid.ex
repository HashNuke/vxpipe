defmodule Vxpipe.Identity.Uuid do
  @moduledoc false
  @spec generate() :: String.t()
  def generate do
    <<a1, a2, a3, a4, b1, b2, c1, c2, d1, d2, e1, e2, e3, e4, e5, e6>> =
      :crypto.strong_rand_bytes(16)

    c1 = Bitwise.band(c1, 0x0F) |> Bitwise.bor(0x40)
    d1 = Bitwise.band(d1, 0x3F) |> Bitwise.bor(0x80)

    :io_lib.format(
      "~2.16.0b~2.16.0b~2.16.0b~2.16.0b-~2.16.0b~2.16.0b-~2.16.0b~2.16.0b-~2.16.0b~2.16.0b-~2.16.0b~2.16.0b~2.16.0b~2.16.0b~2.16.0b~2.16.0b",
      [a1, a2, a3, a4, b1, b2, c1, c2, d1, d2, e1, e2, e3, e4, e5, e6]
    )
    |> to_string()
  end
end
