defmodule Vxpipe.CallEngine.Speech.ProviderName do
  @moduledoc false
  alias Vxpipe.CallEngine.Speech.Allocation

  def address(allocation), do: {:via, __MODULE__, allocation}

  def register_name(allocation, _pid) do
    if Allocation.valid?(allocation) do
      case Registry.register(Vxpipe.CallEngine.RoomRegistry, key(allocation), nil) do
        {:ok, _partition} -> confirm_registration(allocation)
        {:error, _reason} -> :no
      end
    else
      :no
    end
  end

  def unregister_name(allocation),
    do: Registry.unregister(Vxpipe.CallEngine.RoomRegistry, key(allocation))

  def whereis_name(allocation) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, key(allocation)) do
      [{pid, _value}] -> pid
      [] -> :undefined
    end
  end

  def send(allocation, message) do
    case whereis_name(allocation) do
      :undefined -> exit(:badarg)
      pid -> Kernel.send(pid, message)
    end
  end

  defp confirm_registration(allocation) do
    if Allocation.valid?(allocation) do
      :yes
    else
      unregister_name(allocation)
      :no
    end
  end

  defp key(allocation), do: {__MODULE__, allocation.generation}
end
