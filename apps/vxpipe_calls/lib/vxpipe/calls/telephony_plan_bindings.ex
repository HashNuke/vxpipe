defmodule Vxpipe.Calls.TelephonyPlanBindings do
  @moduledoc false

  alias Vxpipe.CallEngine.{Error, ResolvedCallPlan}
  alias Vxpipe.CallEngine.Telephony.ServiceReference
  alias Vxpipe.Calls.TelephonyServices

  def pin(%ResolvedCallPlan{} = plan, options) do
    with {:ok, references} <- resolve_references(plan, options) do
      participants =
        Map.new(plan.participants, fn
          {ref, %{connection: %{service: name}} = participant} when is_binary(name) ->
            {ref, %{participant | telephony_service: Map.fetch!(references, name)}}

          participant ->
            participant
        end)

      {:ok, %{plan | participants: participants}}
    end
  end

  def with_active(%ResolvedCallPlan{} = plan, options, operation) do
    with {:ok, requirements} <- pinned_requirements(plan) do
      case requirements do
        [] ->
          operation.()

        [first | _] ->
          case TelephonyServices.with_active(plan.tenant_id, requirements, options, operation) do
            {:error, {:provider_credential_unavailable, path}} ->
              unavailable(path)

            {:error, reason}
            when reason in [:repository_unavailable, :telephony_services_unavailable] ->
              unavailable(first.path)

            result ->
              result
          end
      end
    end
  end

  defp resolve_references(plan, options) do
    plan
    |> service_participants()
    |> Enum.uniq_by(fn {_ref, participant} -> participant.connection.service end)
    |> Enum.reduce_while({:ok, %{}}, fn {ref, participant}, {:ok, references} ->
      name = participant.connection.service

      case TelephonyServices.resolve(plan.tenant_id, name, options) do
        {:ok, snapshot} ->
          {:cont, {:ok, Map.put(references, name, TelephonyServices.reference(snapshot.service))}}

        {:error, _reason} ->
          {:halt, unavailable(service_path(ref))}
      end
    end)
  end

  defp pinned_requirements(plan) do
    plan
    |> service_participants()
    |> Enum.reduce_while({:ok, []}, fn {ref, participant}, {:ok, requirements} ->
      name = participant.connection.service

      case participant do
        %{telephony_service: %ServiceReference{tenant_id: tenant, name: ^name} = reference}
        when tenant == plan.tenant_id ->
          requirement = %{name: name, path: service_path(ref), reference: reference}
          {:cont, {:ok, [requirement | requirements]}}

        _unbound ->
          {:halt, unavailable(service_path(ref))}
      end
    end)
    |> case do
      {:ok, requirements} -> {:ok, Enum.reverse(requirements)}
      error -> error
    end
  end

  defp service_participants(plan) do
    plan.participants
    |> Enum.filter(fn
      {_ref, %{connection: %{service: name}}} when is_binary(name) -> true
      _local -> false
    end)
    |> Enum.sort_by(fn {ref, participant} -> {participant.connection.service, ref} end)
  end

  defp service_path(ref), do: ["participants", ref, "connection", "service"]

  defp unavailable(path) do
    {:error,
     Error.new(
       :provider_credential_unavailable,
       "The selected tenant provider credential is unavailable.", details: %{"path" => path})}
  end
end
