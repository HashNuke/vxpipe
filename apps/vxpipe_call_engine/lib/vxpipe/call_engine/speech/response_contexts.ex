defmodule Vxpipe.CallEngine.Speech.ResponseContexts do
  @moduledoc false

  # Interim input-only retention: accepted origins live until allocation teardown.
  # Response/tool holds and engine-authorized root retirement are a separate gate.
  @maximum_contexts 16

  def new, do: %{contexts: %{}, pending: nil}

  def status(owner, context), do: Map.get(owner.contexts, context, :unknown)

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
  ignored and the currently staged context is never removed.
  """
  def retire(owner, contexts) when is_list(contexts) do
    Enum.reduce(contexts, owner, fn context, owner ->
      if status(owner, context) == :accepted do
        %{owner | contexts: Map.delete(owner.contexts, context)}
      else
        owner
      end
    end)
  end

  def retire(owner, _contexts), do: owner
end
