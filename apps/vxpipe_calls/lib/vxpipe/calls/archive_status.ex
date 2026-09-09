defmodule Vxpipe.Calls.ArchiveStatus do
  @moduledoc "Describes whether one call's asynchronous private archive closed completely."

  alias Vxpipe.Calls.CallFact

  @maximum_missing_sequence_samples 100

  @derive {Inspect, except: [:closure]}
  @enforce_keys [
    :state,
    :complete?,
    :last_sequence,
    :missing_sequence_count,
    :missing_sequences,
    :closure
  ]
  defstruct @enforce_keys

  @type state :: :complete | :incomplete | :unconfirmed
  @type t :: %__MODULE__{
          state: state(),
          complete?: boolean(),
          last_sequence: pos_integer() | nil,
          missing_sequence_count: non_neg_integer(),
          missing_sequences: [pos_integer()],
          closure: CallFact.t() | nil
        }

  @spec from_facts([CallFact.t()]) :: t()
  def from_facts(facts) when is_list(facts) do
    sequences = facts |> Enum.map(& &1.sequence) |> Enum.uniq() |> Enum.sort()
    {missing_sequence_count, missing_sequences} = missing_sequences(sequences)
    last_sequence = List.last(sequences)
    closure = latest_closure(facts)

    complete? =
      not is_nil(closure) and closure.sequence == last_sequence and
        missing_sequence_count == 0 and closure.payload["incomplete"] == false

    %__MODULE__{
      state: status(closure, complete?),
      complete?: complete?,
      last_sequence: last_sequence,
      missing_sequence_count: missing_sequence_count,
      missing_sequences: missing_sequences,
      closure: closure
    }
  end

  defp latest_closure(facts) do
    Enum.reduce(facts, nil, fn
      %CallFact{kind: :archive_stream_closed} = fact, nil -> fact
      %CallFact{kind: :archive_stream_closed, sequence: sequence} = fact,
      %CallFact{sequence: prior_sequence}
      when sequence > prior_sequence ->
        fact

      _fact, closure ->
        closure
    end)
  end

  defp status(nil, _complete?), do: :unconfirmed
  defp status(_closure, true), do: :complete
  defp status(_closure, false), do: :incomplete

  defp missing_sequences(sequences) do
    {_expected, count, samples} =
      Enum.reduce(sequences, {1, 0, []}, fn sequence, {expected, count, samples} ->
        gap_count = max(sequence - expected, 0)
        sample_capacity = @maximum_missing_sequence_samples - length(samples)

        samples =
          if gap_count > 0 and sample_capacity > 0 do
            samples ++ Enum.take(expected..(sequence - 1), sample_capacity)
          else
            samples
          end

        {max(expected, sequence + 1), count + gap_count, samples}
      end)

    {count, samples}
  end
end
