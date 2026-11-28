defmodule Vxpipe.Calls.CallSpecGuardrailIds do
  @moduledoc "Assigns guardrail question IDs when saving a call-spec revision."

  alias Vxpipe.CallEngine.Error

  @events ~w(before_turn after_turn before_outgoing_transfer)

  def supported?(%{"schema_version" => "20261128.01"}), do: true
  def supported?(_), do: false

  def has_guardrail_questions?(source), do: rows(source) != []

  def known_ids(source) do
    owners = Map.new(people(source), fn {ref, _} -> {ref, MapSet.new()} end)

    Enum.reduce(rows(source), owners, fn
      %{owner: owner, id: {:ok, id}}, acc when is_binary(id) ->
        Map.update!(acc, owner, &MapSet.put(&1, id))

      _, acc ->
        acc
    end)
  end

  def assign_new(source, generator) do
    questions = rows(source)

    case Enum.find(questions, &(&1.id != :error)) do
      nil -> allocate(source, questions, %{}, generator)
      row -> invalid(row, "must not include an ID on creation; IDs are assigned by the backend")
    end
  end

  def assign_update(source, known, generator) do
    questions = rows(source)

    with :ok <- verify(source, questions, known) do
      allocate(source, questions, known, generator)
    end
  end

  # New IDs were already assigned before the conflicting insert. Only the IDs
  # supplied by the caller must survive in the newly winning predecessor.
  def verify_persisted(source, winning, original) do
    original_ids = all_ids(original)
    winning_ids = all_ids(winning)

    {existing, generated} =
      Enum.split_with(rows(source), fn %{id: {:ok, id}} -> MapSet.member?(original_ids, id) end)

    case Enum.find(generated, fn %{id: {:ok, id}} -> MapSet.member?(winning_ids, id) end) do
      nil -> verify(source, existing, winning)
      row -> invalid(row, "conflicts with a question assigned by another save")
    end
  end

  # Leave malformed participants, event lists and questions intact for the
  # call-spec validator. Both validation and assignment visit the same paths.
  defp rows(source) do
    for {owner, %{"guardrails" => guardrails}} <- Enum.sort(people(source)),
        is_map(guardrails),
        event <- @events,
        list = Map.get(guardrails, event),
        is_list(list),
        {question, index} <- Enum.with_index(list),
        is_map(question) do
      %{owner: owner, event: event, index: index, id: Map.fetch(question, "id")}
    end
  end

  defp people(%{"participants" => participants}) when is_map(participants), do: participants
  defp people(_), do: %{}

  defp verify(source, questions, known) do
    # A one-to-one rename may retain IDs. An existing owner's incoming IDs
    # can never establish ownership for a second participant.
    owners =
      for {owner, ids} <- known, id <- ids, reduce: %{} do
        acc -> Map.update(acc, id, [owner], &[owner | &1])
      end

    references = for %{id: {:ok, id}} = row <- questions, do: {row, id}

    moves =
      for {row, id} <- references,
          [previous] <- [Map.get(owners, id, [])],
          row.owner != previous,
          do: {previous, row.owner}

    renames =
      moves
      |> Enum.uniq()
      |> Enum.filter(fn {previous, current} ->
        not Map.has_key?(people(source), previous) and not Map.has_key?(known, current)
      end)

    destinations = Enum.group_by(Enum.uniq(moves), &elem(&1, 0), &elem(&1, 1))
    origins = Enum.group_by(Enum.uniq(moves), &elem(&1, 1), &elem(&1, 0))

    allowed =
      for {old, new} <- renames,
          destinations[old] == [new],
          origins[new] == [old],
          into: %{},
          do: {new, old}

    Enum.reduce_while(references, MapSet.new(), fn {row, id}, seen ->
      old = Map.get(allowed, row.owner, row.owner)

      cond do
        not is_binary(id) or not Map.has_key?(owners, id) ->
          {:halt, invalid(row, "must reference a stored question")}

        old not in Map.fetch!(owners, id) ->
          {:halt, invalid(row, "must reference a question stored for this participant")}

        MapSet.member?(seen, {row.owner, id}) ->
          {:halt, invalid(row, "must be unique within the participant")}

        true ->
          {:cont, MapSet.put(seen, {row.owner, id})}
      end
    end)
    |> case do
      %MapSet{} -> :ok
      error -> error
    end
  end

  defp allocate(source, questions, known, generator) do
    {assigned, _used} =
      Enum.reduce(questions, {source, all_ids(known)}, fn
        %{id: :error} = row, {source, used} ->
          id = fresh_id(generator, used)
          path = ["participants", row.owner, "guardrails", row.event, Access.at(row.index), "id"]
          {put_in(source, path, id), MapSet.put(used, id)}

        _, state ->
          state
      end)

    {:ok, assigned}
  end

  defp fresh_id(generator, used) do
    id = generator.()
    if MapSet.member?(used, id), do: fresh_id(generator, used), else: id
  end

  defp all_ids(known), do: Enum.reduce(Map.values(known), MapSet.new(), &MapSet.union/2)

  def default_id, do: "q_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  defp invalid(row, reason) do
    path = [
      "participants",
      row.owner,
      "guardrails",
      row.event,
      Integer.to_string(row.index),
      "id"
    ]

    {:error,
     Error.new(:invalid_call_spec, "The call spec is invalid.",
       details: %{"path" => path, "reason" => reason}
     )}
  end
end
