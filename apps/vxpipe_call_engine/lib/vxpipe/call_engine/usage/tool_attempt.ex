defmodule Vxpipe.CallEngine.Usage.ToolAttempt do
  @moduledoc false

  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.Tool.InvocationSubmission

  alias Vxpipe.CallEngine.Usage.{
    Attribution,
    Measurement,
    Observation,
    ToolProvider
  }

  @derive {Inspect,
           only: [
             :attempt_id,
             :call_id,
             :activation_id,
             :provider,
             :tool_call_id
           ]}
  @enforce_keys [
    :attempt_id,
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :activation_id,
    :turn_id,
    :tool_call_id,
    :tool_name,
    :provider
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @spec start(String.t(), String.t(), InvocationSubmission.t(), DateTime.t()) ::
          {:ok, t(), [Observation.t()]} | {:error, :invalid_tool_usage}
  def start(
        call_id,
        activation_id,
        %InvocationSubmission{} = submission,
        %DateTime{} = observed_at
      )
      when is_binary(call_id) and call_id != "" and is_binary(activation_id) and
             activation_id != "" do
    context = submission.context

    with {:ok, provider} <- ToolProvider.from_binding(submission.binding),
         {:ok, attribution} <- attribution(submission, activation_id),
         {:ok, measurement} <- invocation_measurement(),
         attempt = %__MODULE__{
           attempt_id: Id.generate(:tool_attempt),
           tenant_id: context.tenant_id,
           call_id: call_id,
           room_id: context.room_id,
           incarnation_id: context.incarnation_id,
           participant_id: context.agent_participant_id,
           activation_id: activation_id,
           turn_id: context.correlation_id,
           tool_call_id: submission.invocation_id,
           tool_name: submission.tool_name,
           provider: provider
         },
         {:ok, observation} <-
           observation(attempt, attribution, measurement, :in_progress, observed_at) do
      {:ok, attempt, [observation]}
    else
      _invalid -> {:error, :invalid_tool_usage}
    end
  end

  def start(_call_id, _activation_id, _submission, _observed_at),
    do: {:error, :invalid_tool_usage}

  @spec finish(t(), Vxpipe.CallEngine.Tool.InvocationCompletion.t(), DateTime.t()) ::
          {:ok, [Observation.t()]} | {:error, :invalid_tool_usage}
  def finish(%__MODULE__{} = attempt, completion, %DateTime{} = observed_at) do
    with true <- matching_completion?(attempt, completion),
         outcome when outcome in [:succeeded, :failed, :unknown] <- outcome(completion),
         {:ok, attribution} <- attribution(attempt),
         {:ok, observation} <- observation(attempt, attribution, nil, outcome, observed_at) do
      {:ok, [observation]}
    else
      _invalid -> {:error, :invalid_tool_usage}
    end
  end

  def finish(_attempt, _completion, _observed_at), do: {:error, :invalid_tool_usage}

  defp attribution(submission, activation_id) do
    context = submission.context

    Attribution.new(
      room_id: context.room_id,
      incarnation_id: context.incarnation_id,
      participant_id: context.agent_participant_id,
      activation_id: activation_id,
      turn_id: context.correlation_id,
      tool_call_id: submission.invocation_id
    )
  end

  defp attribution(attempt) do
    Attribution.new(
      room_id: attempt.room_id,
      incarnation_id: attempt.incarnation_id,
      participant_id: attempt.participant_id,
      activation_id: attempt.activation_id,
      turn_id: attempt.turn_id,
      tool_call_id: attempt.tool_call_id
    )
  end

  defp invocation_measurement do
    Measurement.new(
      component: "invocations",
      unit: :requests,
      quantity: 1,
      mode: :delta,
      status: :final,
      provenance: :locally_measured
    )
  end

  defp observation(attempt, attribution, measurement, outcome, observed_at) do
    Observation.new(
      id: observation_id(attempt.attempt_id, observation_component(measurement)),
      tenant_id: attempt.tenant_id,
      call_id: attempt.call_id,
      attempt_id: attempt.attempt_id,
      capability: :tool,
      provider: attempt.provider,
      attribution: attribution,
      measurement: measurement,
      outcome: outcome,
      observed_at: observed_at
    )
  end

  defp observation_id(attempt_id, component) do
    digest = :crypto.hash(:sha256, attempt_id <> ":" <> component)
    "uobs_" <> Base.url_encode64(digest, padding: false)
  end

  defp observation_component(%Measurement{component: component}), do: component
  defp observation_component(nil), do: "terminal"

  defp matching_completion?(attempt, completion) do
    is_struct(completion, Vxpipe.CallEngine.Tool.InvocationCompletion) and
      completion.invocation_id == attempt.tool_call_id and
      completion.tool_name == attempt.tool_name
  end

  defp outcome(%{outcome: {:ok, _result}}), do: :succeeded
  defp outcome(%{outcome: {:error, :unknown}}), do: :unknown
  defp outcome(%{outcome: {:error, _reason}}), do: :failed
  defp outcome(_completion), do: :invalid
end
