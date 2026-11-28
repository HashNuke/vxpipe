defmodule Vxpipe.CallEngine.RoomAuthority.DecisionsPublication do
  @moduledoc """
  Trusted archive publication for Decisions (Guardrails) outcomes.

  The live producer (`Guardrails.Participant`) captures the logical evaluation,
  per-question results and per-attempt metadata. This module validates the
  report against the owning activation, resolves the allowed source interval,
  and emits bounded private facts through the existing archive lifecycle.

  Facts use `Recorder.internal_fact/3`, so they never enter the public event
  projection (`EventPublisher.publish/3` is not used here). Usage uses the
  normal `usage_observed` archive kind with stable delivery IDs, so duplicate
  delivery dedupes and late corrections supersede without reopening the gate.
  """

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Guardrails.{Emission, Evidence}

  alias Vxpipe.CallEngine.Usage.{
    ArchiveProjection,
    Attribution,
    Measurement,
    Observation,
    ProviderContext
  }

  @max_facts 64

  @doc """
  Records one terminal evaluation report into the archive recorder.

  Returns the updated state. Invalid activation, mismatched call scope, or an
  invalid report leaves the state unchanged (drops the report).
  """
  @spec record(map(), map()) :: map()
  def record(state, %{kind: :decisions_feedback_dispatched} = receipt) do
    with :ok <- validate_scope(state, receipt),
         :ok <- validate_activation(state, receipt),
         {:ok, policy} <- source_policy(state, receipt),
         {:ok, attrs} <- Emission.feedback_fact(receipt, policy) do
      %{
        state
        | archive_recorder: Recorder.internal_fact(state.archive_recorder, receipt.kind, attrs)
      }
    else
      _ -> state
    end
  end

  def record(%{} = state, %{} = report) do
    with {:ok, report} <- Emission.build_report(report),
         :ok <- validate_scope(state, report),
         :ok <- validate_activation(state, report),
         {:ok, source_policy} <- source_policy(state, report),
         envelope <- %{occurred_at: report.ended_at, source_policy: source_policy},
         {:ok, eval_attrs} <- Emission.evaluation_fact(report, envelope),
         {:ok, question_facts} <- Emission.question_facts(report, envelope),
         {:ok, attempt_facts} <- Emission.attempt_facts(report, envelope),
         facts <- [{:decisions_evaluation, eval_attrs} | question_facts ++ attempt_facts],
         true <- length(facts) <= @max_facts,
         {:ok, observations} <- Emission.usage_observations(report, identity(state, report)) do
      recorder =
        Enum.reduce(facts, state.archive_recorder, fn {kind, attrs}, recorder ->
          Recorder.internal_fact(recorder, kind, attrs)
        end)

      recorder =
        Enum.reduce(observations, recorder, fn observation, acc ->
          Recorder.internal_fact(acc, :usage_observed, ArchiveProjection.attributes(observation))
        end)

      %{state | archive_recorder: recorder}
    else
      _invalid -> state
    end
  end

  @doc """
  Records late billable usage after cancellation without emitting a new
  evaluation. Used for the correction path; never reopens the gate.
  """
  @spec record_usage(map(), [struct()]) :: map()
  def record_usage(%{} = state, observations) when is_list(observations) do
    valid =
      Enum.filter(observations, fn observation ->
        valid_late_observation?(state, observation)
      end)

    recorder =
      Enum.reduce(valid, state.archive_recorder, fn observation, acc ->
        Recorder.internal_fact(acc, :usage_observed, ArchiveProjection.attributes(observation))
      end)

    %{state | archive_recorder: recorder}
  end

  def record_usage(%{} = state, _observations), do: state

  # --- validation ---

  defp validate_scope(state, report) do
    snapshot = Map.get(state, :snapshot, %{})
    recorder = Map.get(state, :archive_recorder)

    trusted_tenant = snapshot_tenant(snapshot)
    trusted_call = snapshot_call(snapshot) || recorder_call(recorder)
    trusted_room = snapshot_room(snapshot) || recorder_room(recorder)

    report_tenant = report_tenant(report)
    report_call = Map.get(report, :call_id)
    report_room = Map.get(report, :room_id)
    report_incarnation = Map.get(report, :incarnation_id)
    trusted_incarnation = snapshot_incarnation(snapshot)

    with true <- is_binary(report_tenant) and report_tenant == trusted_tenant,
         true <- is_binary(report_call) and report_call == trusted_call,
         true <- is_binary(report_room) and report_room == trusted_room,
         true <-
           is_binary(report_incarnation) and report_incarnation == trusted_incarnation do
      :ok
    else
      _ -> :error
    end
  end

  defp validate_activation(state, report) do
    recorder = Map.get(state, :archive_recorder)

    cond do
      is_nil(recorder) ->
        :error

      not is_binary(Map.get(report, :participant_id)) or
          not is_binary(Map.get(report, :activation_id)) ->
        :error

      true ->
        expected =
          try do
            Recorder.participant_activation(recorder, report.participant_id)
          rescue
            _ -> :error
          catch
            _, _ -> :error
          end

        if expected == report.activation_id, do: :ok, else: :error
    end
  end

  defp source_policy(
         state,
         %{
           policy_revision: _,
           policy_digest: _,
           source_policy_revision: _,
           event: event,
           source_participant_id: _
         } = report
       )
       when event in [:before_turn, :after_turn, :before_outgoing_transfer] do
    base = %{
      "revision" => report.policy_revision,
      "policy_digest" => report.policy_digest
    }

    revision = report.source_policy_revision

    source =
      if report.event == :before_turn,
        do: report.source_participant_id,
        else: report.source_participant_id || report.participant_id

    interval =
      Evidence.storage_policy(Map.get(state, :transcript_router), report, source, revision)

    {:ok, Map.merge(base, interval)}
  end

  defp source_policy(_state, _report), do: :error

  defp identity(state, _report) do
    snapshot = Map.get(state, :snapshot, %{})
    recorder = Map.get(state, :archive_recorder)

    %{
      tenant_id: snapshot_tenant(snapshot),
      call_id: snapshot_call(snapshot) || recorder_call(recorder),
      room_id: snapshot_room(snapshot) || recorder_room(recorder),
      incarnation_id: snapshot_incarnation(snapshot)
    }
  end

  defp valid_late_observation?(
         state,
         %Observation{
           capability: :decisions,
           attribution: %Attribution{} = attribution,
           provider: %ProviderContext{},
           measurement: %Measurement{
             unit: :tokens,
             component: component,
             quantity: quantity,
             status: :correction,
             mode: :cumulative,
             provenance: :provider_reported
           }
         } = observation
       )
       when component in ["input_tokens", "output_tokens", "total_tokens"] and
              is_integer(quantity) and quantity >= 0 do
    scope = %{
      tenant_id: observation.tenant_id,
      call_id: observation.call_id,
      room_id: attribution.room_id,
      incarnation_id: attribution.incarnation_id
    }

    is_binary(observation.attempt_id) and is_binary(attribution.participant_id) and
      is_binary(attribution.activation_id) and validate_scope(state, scope) == :ok
  end

  defp valid_late_observation?(_state, _observation), do: false

  defp report_tenant(%{tenant_id: tenant}) when is_binary(tenant), do: tenant
  defp report_tenant(_), do: nil

  defp snapshot_tenant(%{tenant_id: tenant}), do: tenant
  defp snapshot_tenant(_), do: nil

  defp snapshot_call(%{call_id: call}), do: call
  defp snapshot_call(_), do: nil

  defp snapshot_room(%{room_id: room}), do: room
  defp snapshot_room(_), do: nil

  defp snapshot_incarnation(%{incarnation_id: incarnation}), do: incarnation
  defp snapshot_incarnation(_), do: nil

  defp recorder_call(%{port: %{call_id: call_id}}), do: call_id
  defp recorder_call(_), do: nil

  defp recorder_room(%{port: %{room_id: room_id}}), do: room_id
  defp recorder_room(_), do: nil
end
