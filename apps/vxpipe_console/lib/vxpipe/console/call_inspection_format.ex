defmodule Vxpipe.Console.CallInspectionFormat do
  @moduledoc false

  @spec timestamp(DateTime.t() | nil) :: String.t()
  def timestamp(nil), do: "Not started"

  def timestamp(%DateTime{} = value) do
    Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")
  end

  @spec state(atom()) :: String.t()
  def state(:prepared), do: "Prepared"
  def state(:admitting), do: "Admitting"
  def state(:running), do: "Running record"
  def state(:ended), do: "Ended"
  def state(:failed), do: "Failed"

  @spec revision(non_neg_integer() | nil) :: String.t()
  def revision(nil), do: "None"
  def revision(value) when is_integer(value), do: "r#{value}"
end
