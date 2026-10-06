defmodule Vxpipe.Calls.OutgoingCallFact do
  @moduledoc "Closed, non-payload-bearing outgoing dial lifecycle evidence."

  @outcomes ~w(answered no_answer busy rejected failed machine unknown)
  @kinds [:outgoing_dial_submitted, :outgoing_call_answered, :outgoing_dial_ended]
  @outcome_atoms Map.new(
                   [:answered, :no_answer, :busy, :rejected, :failed, :machine, :unknown],
                   &{Atom.to_string(&1), &1}
                 )

  def kind?(kind), do: kind in @kinds

  def validate(:outgoing_dial_submitted, payload) when payload == %{}, do: :ok

  def validate(:outgoing_call_answered, %{"outcome" => "answered"} = payload)
      when map_size(payload) == 1, do: :ok

  def validate(:outgoing_dial_ended, %{"outcome" => outcome} = payload)
      when map_size(payload) == 1 and outcome in @outcomes, do: :ok

  def validate(kind, _payload) when kind in @kinds, do: {:error, :invalid_call_fact}
  def validate(_kind, _payload), do: :ok

  def outcome(%{"outcome" => name}), do: Map.fetch!(@outcome_atoms, name)
end
