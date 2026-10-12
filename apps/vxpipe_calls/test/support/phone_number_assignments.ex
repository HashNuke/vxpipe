defmodule Vxpipe.Calls.TestPhoneNumberAssignments do
  @moduledoc false
  def list_number_assignments({tenant, assignments}, tenant, numbers) do
    {:ok, Enum.filter(assignments, &(&1.number in numbers))}
  end
end
