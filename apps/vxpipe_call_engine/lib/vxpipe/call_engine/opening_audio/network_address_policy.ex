defmodule Vxpipe.CallEngine.OpeningAudio.NetworkAddressPolicy do
  @moduledoc false

  @type address :: :inet.ip_address()

  @spec select_public([address()]) :: {:ok, address()} | {:error, :unsafe_address}
  def select_public(addresses) when is_list(addresses) do
    case Enum.uniq(addresses) do
      [] ->
        {:error, :unsafe_address}

      resolved ->
        if Enum.all?(resolved, &public_address?/1) do
          {:ok, Enum.min(resolved)}
        else
          {:error, :unsafe_address}
        end
    end
  end

  @spec public_address?(term()) :: boolean()
  def public_address?({a, b, _c, _d}) do
    cond do
      a == 0 -> false
      a == 10 -> false
      a == 100 and b in 64..127 -> false
      a == 127 -> false
      a == 169 and b == 254 -> false
      a == 172 and b in 16..31 -> false
      a == 192 and b in [0, 168] -> false
      a == 198 and b in [18, 19, 51] -> false
      a == 203 and b == 0 -> false
      a >= 224 -> false
      true -> true
    end
  end

  def public_address?({0, 0, 0, 0, 0, 0xFFFF, high, low}) do
    public_address?({div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)})
  end

  def public_address?({first, second, _c, _d, _e, _f, _g, _h}) do
    global_unicast? = Bitwise.band(first, 0xE000) == 0x2000
    documentation? = first == 0x2001 and second == 0x0DB8
    reserved_2001? = first == 0x2001 and second <= 0x01FF
    six_to_four? = first == 0x2002

    global_unicast? and not documentation? and not reserved_2001? and not six_to_four?
  end

  def public_address?(_address), do: false
end
