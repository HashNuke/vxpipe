defmodule Vxpipe.CallEngine.PlanStartup.Guardrails do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.{CapabilitySelection, Guardrails}
  alias Vxpipe.CallEngine.{CredentialSource, Error, ProviderCredential}
  alias Vxpipe.Providers.Registry

  def options(plan, %{guardrails: %Guardrails{} = policy} = participant, options) do
    if Guardrails.empty?(policy) do
      {:ok, []}
    else
      runtime = Keyword.get(options, :agent_runtime, [])

      with :ok <-
             Guardrails.check_feedback_budget(
               policy,
               Keyword.get(runtime, :maximum_model_context_bytes, 256 * 1_024)
             ),
           {:ok, adapter} <-
             bind(plan.decisions, plan.tenant_id, participant.participant_id, runtime, options) do
        {:ok,
         [
           guardrails:
             [
               policy: policy,
               adapter: adapter,
               participant_id: participant.participant_id,
               activation_id: participant.activation_id,
               policy_revision: plan.call_spec_revision,
               policy_digest: Guardrails.digest(policy),
               selected_provider: decisions_provider(plan),
               selected_model: decisions_model(plan),
               tenant_id: plan.tenant_id,
               call_id: plan.call_id,
               room_id: plan.room_id,
               incarnation_id: Keyword.get(options, :incarnation_id),
               enforce_input_route?: is_binary(Keyword.get(options, :incarnation_id))
             ] ++ Keyword.take(runtime, [:maximum_pending_requests]) ++ emission_options(plan)
         ]}
      else
        {:error, :oversized} ->
          {:error,
           Error.new(
             :unsupported_call_plan,
             "Guardrail feedback exceeds the model request budget.",
             details: %{
               "path" => ["participants", participant.call_spec_key, "guardrails"],
               "reason" => "Shorten the guardrail responses or fallback questions."
             }
           )}

        _unavailable ->
          {:error,
           Error.new(:unsupported_call_plan, "The Decisions configuration is unavailable.",
             details: %{
               "path" => ["defaults", "capabilities", "decisions"],
               "reason" => "requires a supported model and available tenant credential"
             }
           )}
      end
    end
  end

  # Previously prepared plans may predate the participant field.
  def options(_plan, _participant, _options), do: {:ok, []}

  defp bind(
         %CapabilitySelection{provider: "fixture"},
         _tenant_id,
         _participant_id,
         runtime,
         _options
       ) do
    case Keyword.fetch(runtime, :decisions_fixture) do
      {:ok, fixture} when is_function(fixture, 1) -> {:ok, fixture}
      _missing -> {:error, :unavailable}
    end
  end

  defp bind(
         %CapabilitySelection{kind: :decisions} = selection,
         tenant_id,
         participant_id,
         runtime,
         options
       ) do
    with {:ok, adapter} <- Registry.resolve_capability(selection.provider, :decisions),
         {:ok, %ProviderCredential{auth_kind: "api_key", payload: %{"api_key" => key}}} <-
           CredentialSource.resolve(tenant_id, selection, options),
         {:ok, config} <- adapter.new(model: selection.model, api_key: key) do
      transport =
        case Keyword.get(runtime, :decisions_http_plug) do
          nil -> []
          plug -> [plug: plug]
        end

      {:ok,
       fn request ->
         evaluate_opts =
           transport
           |> Keyword.put(:deadline_ms, request.deadline)
           |> put_on_attempt(request)

         with {:ok, input} <-
                Vxpipe.CallEngine.Guardrails.Evidence.packet(
                  request.event,
                  participant_id,
                  request.evidence
                ),
              {:ok, %{probabilities: scores} = result} <-
                adapter.evaluate(
                  config,
                  input,
                  request.questions,
                  evaluate_opts
                ) do
           {:ok, Map.merge(result, %{scores: scores, provider: selection.provider})}
         end
       end}
    end
  end

  defp bind(_selection, _tenant_id, _participant_id, _runtime, _options),
    do: {:error, :unavailable}

  # Trusted emission wiring. RoomAuthority consumes Participant reports only
  # when activation matches and the source interval resolves; unknown
  # intervals default to safe redaction. The participant forwards terminal
  # reports and late billable usage to the owning room, which records through
  # the existing archive recorder. No custom emission funs are accepted: the
  # path is always PlanStartup -> participant -> RoomAuthority -> recorder.
  defp emission_options(plan) do
    tenant_id = plan.tenant_id
    room_id = plan.room_id

    [
      on_emit: fn report when is_map(report) ->
        Vxpipe.CallEngine.RoomAuthority.record_decisions(tenant_id, room_id, report)
      end,
      on_late_usage: fn observations when is_list(observations) ->
        Vxpipe.CallEngine.RoomAuthority.record_decisions_usage(tenant_id, room_id, observations)
      end
    ]
  end

  defp put_on_attempt(opts, %{on_attempt: fun}) when is_function(fun, 1),
    do: Keyword.put(opts, :on_attempt, fun)

  defp put_on_attempt(opts, _request), do: opts

  defp decisions_provider(%{decisions: %CapabilitySelection{provider: provider}}), do: provider
  defp decisions_provider(_plan), do: nil

  defp decisions_model(%{decisions: %CapabilitySelection{model: model}}), do: model
  defp decisions_model(_plan), do: nil
end
