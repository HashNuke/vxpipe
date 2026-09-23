defmodule Vxpipe.CallEngine.Speech.STSInput do
  @moduledoc """
  STS input admission rules beside the shared bounded input slot.

  Audio, explicit text and external turn boundaries share one outstanding
  input command per allocation, which keeps provider delivery ordered. Text
  admission is proven by the in-flight command itself: the provider's
  `:input_submitted` evidence is accepted only while its exact text command
  still owns the slot. The slot records its first submission, so both a duplicate
  during that callback and a late submission after it settle as stale.
  """

  alias Vxpipe.CallEngine.Speech.{Allocation, Event, EventQueue, ResponseContexts}

  @doc false
  def input_evidence_idle?(state) do
    Allocation.valid?(state.allocation) and EventQueue.idle?(state.events) and is_nil(state.input)
  end

  @doc false
  def context_options([]), do: {:ok, %{}}

  def context_options(response_context: context) when is_reference(context),
    do: {:ok, %{response_context: context}}

  def context_options(_options), do: {:error, :invalid_options}

  @doc false
  def stage_context(descriptor, module, command, contexts) do
    case {descriptor.response_start?, Map.fetch(command, :response_context)} do
      {true, {:ok, context}} when is_reference(context) ->
        if function_exported?(module, :submit_input, 3),
          do: ResponseContexts.stage(contexts, context, command.ref),
          else: {:error, :unsupported_operation}

      {true, _missing} ->
        {:error, :invalid_response_context}

      {false, :error} ->
        {:ok, contexts}

      {false, _present} ->
        {:error, :unsupported_operation}
    end
  end

  @doc false
  def finish_context(contexts, command, :ok), do: ResponseContexts.accept(contexts, command.ref)

  def finish_context(contexts, command, _result),
    do: ResponseContexts.rollback(contexts, command.ref)

  @doc "Whether an input-slot command is supported for the descriptor kind."
  def supported?(%{kind: kind}, %{operation: {:push_text, _, _}}), do: kind == :sts

  def supported?(%{kind: :sts} = descriptor, %{operation: {:input_activity, _}}),
    do: descriptor.turn_control != "provider"

  def supported?(%{kind: kind}, command),
    do: kind in [:stt, :sts] and not Map.has_key?(command, :operation)

  @doc "Accept text submission evidence only for the exact in-flight text command."
  def accept_submission(
        %Event{request_ref: reference} = event,
        %{input: %{command: %{operation: {:push_text, admitted, _}}} = input} = state
      )
      when admitted == reference do
    if Map.get(input, :submitted?, false),
      do: {:error, :stale_request},
      else: {:ok, event, %{state | input: Map.put(input, :submitted?, true)}}
  end

  def accept_submission(_event, _state), do: {:error, :stale_request}
end
