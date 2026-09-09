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
    :duplicate_id_count,
    :duplicate_ids,
    :duplicate_sequence_count,
    :duplicate_sequences,
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
          duplicate_id_count: non_neg_integer(),
          duplicate_ids: [String.t()],
          duplicate_sequence_count: non_neg_integer(),
          duplicate_sequences: [pos_integer()],
          closure: CallFact.t() | nil
        }

  @spec from_facts([CallFact.t()]) :: t()
  def from_facts(facts) when is_list(facts) do
    sequences = facts |> Enum.map(& &1.sequence) |> Enum.uniq() |> Enum.sort()
    {missing_sequence_count, missing_sequences} = missing_sequences(sequences)
    {duplicate_id_count, duplicate_ids} = duplicates(facts, & &1.id)
    {duplicate_sequence_count, duplicate_sequences} = duplicates(facts, & &1.sequence)
    last_sequence = List.last(sequences)
    closure = latest_closure(facts)

    complete? =
      not is_nil(closure) and closure.sequence == last_sequence and
        missing_sequence_count == 0 and duplicate_id_count == 0 and
        duplicate_sequence_count == 0 and closure.payload["incomplete"] == false

    %__MODULE__{
      state: status(closure, complete?),
      complete?: complete?,
      last_sequence: last_sequence,
      missing_sequence_count: missing_sequence_count,
      missing_sequences: missing_sequences,
      duplicate_id_count: duplicate_id_count,
      duplicate_ids: duplicate_ids,
      duplicate_sequence_count: duplicate_sequence_count,
      duplicate_sequences: duplicate_sequences,
      closure: closure
    }
  end

  @spec from_metadata(
          non_neg_integer() | nil,
          non_neg_integer(),
          [pos_integer()],
          CallFact.t() | nil
        ) :: t()
  def from_metadata(last_sequence, present_sequence_count, missing_sequences, closure)
      when (is_nil(last_sequence) or (is_integer(last_sequence) and last_sequence > 0)) and
             is_integer(present_sequence_count) and present_sequence_count >= 0 and
             is_list(missing_sequences) and (is_nil(closure) or is_struct(closure, CallFact)) do
    missing_sequence_count = max((last_sequence || 0) - present_sequence_count, 0)

    complete? =
      not is_nil(closure) and closure.sequence == last_sequence and
        missing_sequence_count == 0 and closure.payload["incomplete"] == false

    %__MODULE__{
      state: status(closure, complete?),
      complete?: complete?,
      last_sequence: last_sequence,
      missing_sequence_count: missing_sequence_count,
      missing_sequences: Enum.take(missing_sequences, @maximum_missing_sequence_samples),
      duplicate_id_count: 0,
      duplicate_ids: [],
      duplicate_sequence_count: 0,
      duplicate_sequences: [],
      closure: closure
    }
  end

  defp latest_closure(facts) do
    Enum.reduce(facts, nil, fn
      %CallFact{kind: :archive_stream_closed} = fact, nil ->
        fact

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

  defp duplicates(facts, value) do
    frequencies = Enum.frequencies_by(facts, value)

    duplicate_count =
      Enum.reduce(frequencies, 0, fn {_value, count}, total -> total + max(count - 1, 0) end)

    samples =
      frequencies
      |> Enum.filter(fn {_value, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()
      |> Enum.take(@maximum_missing_sequence_samples)

    {duplicate_count, samples}
  end
end
