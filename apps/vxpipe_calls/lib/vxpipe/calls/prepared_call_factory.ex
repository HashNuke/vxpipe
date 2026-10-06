defmodule Vxpipe.Calls.PreparedCallFactory do
  @moduledoc false

  alias Vxpipe.CallEngine.{CallSpec, CallInvocation, ResolvedCallPlan}

  alias Vxpipe.Calls.{
    CallPlanCompiler,
    CallSpecCredentials,
    CallSpecRevision,
    PreparedCall,
    PublicId
  }

  @spec build(CallSpecRevision.t(), map(), :web | :telephony, keyword()) ::
          {:ok, PreparedCall.t()} | {:error, term()}
  def build(%CallSpecRevision{} = revision, initial_variables, transport, options)
      when is_map(initial_variables) and transport in [:web, :telephony] and is_list(options) do
    with {:ok, call_spec} <-
           CallSpec.new(revision.source,
             resource_id: revision.call_spec_id,
             revision: revision.revision
           ),
         {:ok, call_spec} <- outgoing_destination(call_spec, Keyword.get(options, :outgoing_to)),
         :ok <- CallSpecCredentials.check(call_spec, revision.tenant_key, options),
         {:ok, invocation} <- invocation(revision, initial_variables, transport, options),
         {:ok, plan} <- CallPlanCompiler.compile(call_spec, invocation, options),
         {:ok, plan} <- CallSpecCredentials.pin(call_spec, plan, options),
         {:ok, plan} <- Vxpipe.CallEngine.prepare_call_audio(plan, options) do
      {:ok, prepared_call(plan, revision.routes, initial_variables, options)}
    end
  end

  @phone_number ~r/\A\+[1-9][0-9]{1,14}\z/

  # An outgoing callee either has a fixed number in its call spec or takes the request's
  # `to`. The resolved number is pinned into the plan, so the dial and the plan digest
  # agree on whom this call reaches.
  defp outgoing_destination(%CallSpec{direction: :outgoing} = call_spec, to) do
    callee = Map.fetch!(call_spec.participants, call_spec.entry_caller)

    case {callee.connection.number, to} do
      {nil, nil} ->
        {:error, :to_required}

      {nil, to} when is_binary(to) ->
        if Regex.match?(@phone_number, to) do
          callee = %{callee | connection: %{callee.connection | number: to}}
          {:ok, %{call_spec | participants: Map.put(call_spec.participants, callee.call_spec_key, callee)}}
        else
          {:error, :invalid_to}
        end

      {_fixed, nil} ->
        {:ok, call_spec}

      {_fixed, _to} ->
        {:error, :to_not_allowed}
    end
  end

  defp outgoing_destination(call_spec, nil), do: {:ok, call_spec}
  defp outgoing_destination(_call_spec, _to), do: {:error, :to_not_allowed}

  defp invocation(revision, initial_variables, transport, options) do
    CallInvocation.new(
      %{
        call_spec: %{id: revision.call_spec_id, revision: revision.revision},
        initial_variables: initial_variables,
        transport: %{type: Atom.to_string(transport)}
      },
      tenant_id: revision.tenant_key,
      actor_id: generated_id(options, :actor_id_generator),
      call_id: generated_id(options, :call_id_generator),
      room_id: generated_id(options, :room_id_generator)
    )
  end

  defp prepared_call(%ResolvedCallPlan{} = plan, routes, initial_variables, options) do
    %PreparedCall{
      id: plan.call_id,
      tenant_key: plan.tenant_id,
      call_spec_id: plan.call_spec_id,
      call_spec_revision: plan.call_spec_revision,
      schema_version: plan.schema_version,
      participant_routes: Map.new(routes, &{&1.key, &1.participant_ref}),
      entry_caller: plan.entry_caller,
      entry_receiver: plan.entry_receiver,
      initial_variables: initial_variables,
      plan: plan,
      plan_digest: plan_digest(plan),
      state: :prepared,
      room_id: plan.room_id,
      created_at: now(options),
      started_at: nil,
      ended_at: nil,
      incarnation_id: nil,
      terminal_reason: nil
    }
  end

  defp plan_digest(plan) do
    plan
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp now(options), do: Keyword.get_lazy(options, :now, &DateTime.utc_now/0)

  defp generated_id(options, key) do
    options
    |> Keyword.get(key, &PublicId.uuid/0)
    |> then(& &1.())
  end
end
