defmodule Vxpipe.Calls.PublicId do
  @moduledoc false

  @spec tenant_key() :: String.t()
  def tenant_key, do: tenant_key("")

  @spec api_key() :: String.t()
  def api_key do
    encoded =
      32
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    "vxp_#{encoded}"
  end

  @spec join_token() :: String.t()
  def join_token do
    encoded =
      32
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    "vxj_#{encoded}"
  end

  @spec uuid() :: String.t()
  def uuid do
    <<part1::32, part2::16, _version::4, part3::12, _variant::2, part4::14, part5::48>> =
      :crypto.strong_rand_bytes(16)

    Enum.join(
      [
        hex(part1, 8),
        hex(part2, 4),
        "4#{hex(part3, 3)}",
        hex(Bitwise.bor(0x8000, part4), 4),
        hex(part5, 12)
      ],
      "-"
    )
  end

  defp tenant_key(<<key::binary-size(16), _rest::binary>>), do: key

  defp tenant_key(prefix) do
    # Discard Base64's two symbols and replenish until 16 alphanumeric characters remain.
    characters =
      12
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)
      |> String.replace(["-", "_"], "")

    tenant_key(prefix <> characters)
  end

  defp hex(value, width) do
    value
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(width, "0")
  end
end
