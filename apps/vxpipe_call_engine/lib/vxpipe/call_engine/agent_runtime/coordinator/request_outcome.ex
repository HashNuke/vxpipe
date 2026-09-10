defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.RequestOutcome do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Result
  alias Vxpipe.CallEngine.AgentRuntime.CompletionContinuation
  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.ActiveRequest
  alias Vxpipe.CallEngine.Telemetry

  @ordinary_request_kinds [:caller, :caller_idle, :greeting]

  @type completed_request ::
          {:completed, struct(), Vxpipe.CallEngine.AgentRuntime.Correlation.t()}
  @type outcome :: :advance | {:advance, completed_request()} | {:stop, atom()}

  @spec finish(ActiveRequest.t(), term(), keyword()) :: outcome()
  def finish(
        %ActiveRequest{} = request,
        {:ok, %Result{status: :completed, output: output}},
        options
      )
      when is_binary(output) do
    request = observe_final_output(request, output, options)

    case ActiveRequest.finish(request, output) do
      {:ok, segments} ->
        Enum.each(segments, &emit_text(request, &1, options))
        stop_telemetry(request, :ok, request.first_output_observed?, options)

        case commit_completion(request, options) do
          :advance ->
            send(owner(options), {:vxpipe_capability_text_complete, self(), request.command})
            {:advance, {:completed, request.command, request.correlation}}

          {:stop, _reason} = stop ->
            stop
        end

      {:error, :invalid_response} ->
        fail_committed(request, :invalid_response, options)
    end
  end

  def finish(%ActiveRequest{} = request, {:ok, %Result{status: :cancelled}}, options) do
    fail_uncommitted(request, :interrupted, options)
  end

  def finish(
        %ActiveRequest{} = request,
        {:ok, %Result{status: :failed, reason: reason}},
        options
      ) do
    fail_uncommitted(request, failure_reason(reason), options)
  end

  def finish(%ActiveRequest{} = request, _invalid, options) do
    fail_uncommitted(request, :provider_unavailable, options)
  end

  @spec fail_uncommitted(ActiveRequest.t(), atom(), keyword()) :: outcome()
  def fail_uncommitted(%ActiveRequest{} = request, reason, options) do
    report_failure(request, reason, options)

    case request.kind do
      kind when kind in @ordinary_request_kinds ->
        :advance

      {:completion, continuation} ->
        case CompletionContinuation.release(invocation_registry(options), continuation) do
          :ok -> {:stop, :completion_continuation_failed}
          {:error, :unavailable} -> {:stop, :completion_release_failed}
        end
    end
  end

  defp commit_completion(%ActiveRequest{kind: kind}, _options)
       when kind in @ordinary_request_kinds,
       do: :advance

  defp commit_completion(
         %ActiveRequest{kind: {:completion, continuation}},
         options
       ) do
    case CompletionContinuation.acknowledge(invocation_registry(options), continuation) do
      :ok -> :advance
      {:error, :unavailable} -> {:stop, :completion_acknowledgement_failed}
    end
  end

  defp fail_committed(request, reason, options) do
    report_failure(request, reason, options)

    case request.kind do
      kind when kind in @ordinary_request_kinds ->
        :advance

      {:completion, continuation} ->
        case CompletionContinuation.acknowledge(invocation_registry(options), continuation) do
          :ok -> {:stop, :completion_output_failed}
          {:error, :unavailable} -> {:stop, :completion_acknowledgement_failed}
        end
    end
  end

  defp report_failure(request, reason, options) do
    stop_telemetry(request, reason, request.first_output_observed?, options)
    send(owner(options), {:vxpipe_capability_failed, self(), request.command, reason})
  end

  defp observe_final_output(request, output, options) do
    case ActiveRequest.observe_output(request, output) do
      {request, :first} ->
        Telemetry.model_first_token(request.started_at, provider(options))
        request

      {request, :subsequent} ->
        request
    end
  end

  defp emit_text(request, text, options) do
    send(owner(options), {:vxpipe_capability_text, self(), request.command, text})
  end

  defp stop_telemetry(request, outcome, first_output_observed?, options) do
    Telemetry.model_request_stop(
      request.started_at,
      provider(options),
      outcome,
      first_output_observed?
    )
  end

  defp invocation_registry(options), do: Keyword.fetch!(options, :invocation_registry)
  defp owner(options), do: Keyword.fetch!(options, :owner)
  defp provider(options), do: Keyword.fetch!(options, :provider)

  defp failure_reason(:request_timeout), do: :provider_timeout
  defp failure_reason(:cancelled), do: :interrupted
  defp failure_reason(:provider_unavailable), do: :provider_unavailable
  defp failure_reason(_reason), do: :invalid_response
end
