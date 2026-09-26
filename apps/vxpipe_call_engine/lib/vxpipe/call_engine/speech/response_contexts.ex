defmodule Vxpipe.CallEngine.Speech.ResponseContexts do
  @moduledoc false

  # Interim input-only retention: accepted origins live until allocation teardown.
  # Response/tool holds and engine-authorized root retirement are a separate gate.
  @maximum_contexts 16
  @maximum_retired 16

  def new, do: %{contexts: %{}, pending: nil, retired: []}

  def status(owner, context) do
    cond do
      Map.has_key?(owner.contexts, context) -> Map.fetch!(owner.contexts, context)
      context in owner.retired -> :retired
      true -> :unknown
    end
  end

  def stage(owner, context, command) when is_reference(context) and is_reference(command) do
    cond do
      owner.pending != nil ->
        {:error, :busy}

      status(owner, context) == :unknown and map_size(owner.contexts) >= @maximum_contexts ->
        {:error, :busy}

      true ->
        contexts = Map.put_new(owner.contexts, context, :staged)
        {:ok, %{owner | contexts: contexts, pending: {command, context}}}
    end
  end

  def stage(_owner, _context, _command), do: {:error, :invalid_response_context}

  def accept(%{pending: {command, context}} = owner, command),
    do: %{owner | pending: nil, contexts: Map.put(owner.contexts, context, :accepted)}

  def accept(owner, _command), do: owner

  def rollback(%{pending: {command, context}} = owner, command) do
    contexts =
      if status(owner, context) == :staged,
        do: Map.delete(owner.contexts, context),
        else: owner.contexts

    %{owner | pending: nil, contexts: contexts}
  end

  def rollback(owner, _command), do: owner

  @doc """
  Engine-authorized retirement of accepted contexts. Unknown contexts are
  ignored, the currently staged context is never removed, and retired contexts
  are remembered as a bounded tombstone window so a late event on one is
  discarded gracefully instead of rejected fatally.
  """
  def retire(owner, contexts) when is_list(contexts) do
    Enum.reduce(contexts, owner, fn context, owner ->
      if status(owner, context) == :accepted do
        retired = [context | owner.retired] |> Enum.uniq() |> Enum.take(@maximum_retired)
        %{owner | contexts: Map.delete(owner.contexts, context), retired: retired}
      else
        owner
      end
    end)
  end

  def retire(owner, _contexts), do: owner
end
