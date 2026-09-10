defmodule Vxpipe.CallEngine.Tool.InvocationRecord do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.{
    CompletionLease,
    InvocationCompletion,
    InvocationStatus,
    InvocationSubmission
  }

  @derive {Inspect, only: [:invocation_id, :tool_name, :conversation_mode, :status]}
  @enforce_keys [
    :invocation_id,
    :tool_name,
    :conversation_mode,
    :source_turn_id,
    :fingerprint,
    :submission,
    :worker,
    :monitor,
    :started_at,
    :status
  ]
  defstruct @enforce_keys ++ [completion: nil, lease: nil]

  @type t :: %__MODULE__{}

  @spec new(InvocationSubmission.t(), pid(), reference()) :: t()
  def new(%InvocationSubmission{} = submission, worker, monitor)
      when is_pid(worker) and is_reference(monitor) do
    %__MODULE__{
      invocation_id: submission.invocation_id,
      tool_name: submission.tool_name,
      conversation_mode: submission.conversation_mode,
      source_turn_id: submission.context.correlation_id,
      fingerprint: submission.fingerprint,
      submission: submission,
      worker: worker,
      monitor: monitor,
      started_at: System.monotonic_time(),
      status: :running
    }
  end

  @spec same_submission?(t(), InvocationSubmission.t()) :: boolean()
  def same_submission?(%__MODULE__{} = record, %InvocationSubmission{} = submission) do
    record.fingerprint == submission.fingerprint
  end

  @spec finish(t(), InvocationCompletion.t()) :: {:ok, t()} | {:error, :stale_completion}
  def finish(%__MODULE__{status: :running} = record, %InvocationCompletion{} = completion) do
    if matching_completion?(record, completion) do
      {:ok,
       %{
         record
         | status: :terminal_queued,
           completion: completion,
           worker: nil,
           monitor: nil
       }}
    else
      {:error, :stale_completion}
    end
  end

  def finish(%__MODULE__{}, %InvocationCompletion{}), do: {:error, :stale_completion}

  @spec failed_completion(t()) :: InvocationCompletion.t()
  def failed_completion(%__MODULE__{} = record) do
    %InvocationCompletion{
      invocation_id: record.invocation_id,
      tool_name: record.tool_name,
      conversation_mode: record.conversation_mode,
      context: record.submission.context,
      outcome: {:error, :tool_failed}
    }
  end

  @spec lease(t(), String.t(), reference()) :: {:ok, t(), CompletionLease.t()} | :error
  def lease(%__MODULE__{status: :terminal_queued} = record, consumer_id, lease_id)
      when is_binary(consumer_id) and is_reference(lease_id) do
    lease = %CompletionLease{
      invocation_id: record.invocation_id,
      consumer_id: consumer_id,
      lease_id: lease_id,
      completion: record.completion
    }

    {:ok, %{record | status: :completion_admitted, lease: lease}, lease}
  end

  def lease(%__MODULE__{}, _consumer_id, _lease_id), do: :error

  @spec release(t(), reference()) :: {:ok, t()} | :error
  def release(
        %__MODULE__{
          status: :completion_admitted,
          lease: %CompletionLease{lease_id: lease_id}
        } = record,
        lease_id
      ) do
    {:ok, %{record | status: :terminal_queued, lease: nil}}
  end

  def release(%__MODULE__{}, _lease_id), do: :error

  @spec leased_by?(t(), reference()) :: boolean()
  def leased_by?(
        %__MODULE__{
          status: :completion_admitted,
          lease: %CompletionLease{lease_id: lease_id}
        },
        lease_id
      ),
      do: true

  def leased_by?(%__MODULE__{}, _lease_id), do: false

  @spec status(t()) :: InvocationStatus.t()
  def status(%__MODULE__{} = record) do
    %InvocationStatus{
      invocation_id: record.invocation_id,
      tool_name: record.tool_name,
      conversation_mode: record.conversation_mode,
      source_turn_id: record.source_turn_id,
      status: record.status
    }
  end

  defp matching_completion?(record, completion) do
    completion.invocation_id == record.invocation_id and
      completion.tool_name == record.tool_name and
      completion.conversation_mode == record.conversation_mode and
      completion.context == record.submission.context
  end
end
