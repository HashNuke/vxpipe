defmodule Vxpipe.CallEngine.Tool.InvocationRecord do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.{
    CompletionLease,
    InvocationBinding,
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
    :deadline_ms,
    :started_at,
    :status
  ]
  defstruct @enforce_keys ++
              [
                completion: nil,
                lease: nil,
                usage_attempt: nil,
                model_hold: nil,
                source_state: :active
              ]

  @type t :: %__MODULE__{}

  @type running_execution :: %{
          invocation_id: String.t(),
          binding: Vxpipe.CallEngine.Tool.InvocationBinding.t(),
          arguments: map(),
          context: Vxpipe.CallEngine.Tool.Context.t(),
          worker: pid(),
          completion_target: pid(),
          deadline_ms: integer()
        }

  @spec new(InvocationSubmission.t(), pid(), reference(), integer()) :: t()
  def new(%InvocationSubmission{} = submission, worker, monitor, deadline_ms)
      when is_pid(worker) and is_reference(monitor) and is_integer(deadline_ms) do
    %__MODULE__{
      invocation_id: submission.invocation_id,
      tool_name: submission.tool_name,
      conversation_mode: submission.conversation_mode,
      source_turn_id: submission.context.correlation_id,
      fingerprint: submission.fingerprint,
      submission: submission,
      worker: worker,
      model_hold:
        if(InvocationBinding.announced_action?(submission.binding, submission.arguments),
          do: :announcement
        ),
      monitor: monitor,
      deadline_ms: deadline_ms,
      started_at: System.monotonic_time(),
      status: :running
    }
  end

  @spec running_execution(t(), pid()) :: {:ok, running_execution()} | {:error, :unavailable}
  def running_execution(%__MODULE__{status: :running} = record, completion_target) do
    if System.monotonic_time(:millisecond) < record.deadline_ms do
      {:ok,
       %{
         invocation_id: record.invocation_id,
         binding: record.submission.binding,
         arguments: record.submission.arguments,
         context: record.submission.context,
         worker: record.worker,
         completion_target: completion_target,
         deadline_ms: record.deadline_ms
       }}
    else
      {:error, :unavailable}
    end
  end

  def running_execution(%__MODULE__{}, _completion_target), do: {:error, :unavailable}

  @spec same_submission?(t(), InvocationSubmission.t()) :: boolean()
  def same_submission?(%__MODULE__{} = record, %InvocationSubmission{} = submission) do
    record.fingerprint == submission.fingerprint
  end

  @spec attach_usage(t(), Vxpipe.CallEngine.Usage.ToolAttempt.t()) :: t()
  def attach_usage(%__MODULE__{usage_attempt: nil} = record, usage_attempt)
      when is_struct(usage_attempt, Vxpipe.CallEngine.Usage.ToolAttempt) do
    %{record | usage_attempt: usage_attempt}
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

  def update_source(record, :detach), do: %{record | source_state: :detached}

  def update_source(%{source_state: :active} = record, :interrupt),
    do: %{record | source_state: :interrupted}

  def update_source(%{source_state: :interrupted, status: :running} = record, :resume),
    do: %{record | source_state: :active}

  def update_source(record, _operation), do: record

  @spec lease(t(), String.t(), reference()) :: {:ok, t(), CompletionLease.t()} | :error
  def lease(%__MODULE__{status: :terminal_queued} = record, consumer_id, lease_id)
      when is_binary(consumer_id) and is_reference(lease_id) do
    lease = %CompletionLease{
      invocation_id: record.invocation_id,
      consumer_id: consumer_id,
      lease_id: lease_id,
      completion: record.completion,
      source_retired?: record.source_state != :active
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
      conversation_mode: if(model_held?(record), do: :blocking, else: record.conversation_mode),
      source_turn_id: record.source_turn_id,
      status: record.status
    }
  end

  @spec model_held?(t()) :: boolean()
  def model_held?(record), do: record.model_hold in [:announcement, :room_hangup]

  defp matching_completion?(record, completion) do
    completion.invocation_id == record.invocation_id and
      completion.tool_name == record.tool_name and
      completion.conversation_mode == record.conversation_mode and
      completion.context == record.submission.context
  end
end
