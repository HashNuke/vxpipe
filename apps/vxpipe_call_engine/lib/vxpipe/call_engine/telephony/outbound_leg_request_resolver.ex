defmodule Vxpipe.CallEngine.Telephony.OutboundLegRequestResolver do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.{ConnectionIntent, NumberFromVariable}
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.ResolvedCallPlan.{Participant, VariableSection}
  alias Vxpipe.CallEngine.Telephony.OutboundLegRequest

  @spec resolve(ResolvedCallPlan.t(), Participant.t(), String.t()) ::
          {:ok, OutboundLegRequest.t()} | {:error, :invalid_outbound_destination}
  def resolve(
        %ResolvedCallPlan{} = plan,
        %Participant{
          kind: :human,
          connection:
            %ConnectionIntent{
              service: service,
              mode: :dial,
              admission: admission
            } = connection
        } = participant,
        incarnation_id
      )
      when is_binary(service) and is_binary(incarnation_id) do
    with {:ok, purpose} <- purpose(plan, participant, admission),
         {:ok, number} <- destination_number(plan, connection) do
      request = %OutboundLegRequest{
        tenant_id: plan.tenant_id,
        actor_id: plan.actor_id,
        call_id: plan.call_id,
        room_id: plan.room_id,
        incarnation_id: incarnation_id,
        participant_id: participant.participant_id,
        service_id: service,
        service_reference: participant.telephony_service,
        to: number,
        purpose: purpose,
        room_owner: if(purpose == :initial, do: self()),
        attempt_id: if(purpose == :initial, do: make_ref())
      }

      if OutboundLegRequest.valid?(request),
        do: {:ok, request},
        else: {:error, :invalid_outbound_destination}
    end
  end

  def resolve(%ResolvedCallPlan{}, %Participant{}, _incarnation_id) do
    {:error, :invalid_outbound_destination}
  end

  defp purpose(_plan, _participant, :transfer), do: {:ok, :transfer}

  defp purpose(%{direction: :outgoing, entry_caller: key}, %{call_spec_key: key}, :start_call),
    do: {:ok, :initial}

  defp purpose(_plan, _participant, _admission), do: {:error, :invalid_outbound_destination}

  defp destination_number(_plan, %ConnectionIntent{number: number}) when is_binary(number) do
    {:ok, number}
  end

  defp destination_number(
         plan,
         %ConnectionIntent{
           number_from_variable: %NumberFromVariable{section: section, variable: variable}
         }
       ) do
    with %VariableSection{value: value} when is_map(value) <-
           Map.get(plan.call_variables.sections, section),
         number when is_binary(number) <- Map.get(value, variable) do
      {:ok, number}
    else
      _missing_or_invalid -> {:error, :invalid_outbound_destination}
    end
  end

  defp destination_number(_plan, %ConnectionIntent{}) do
    {:error, :invalid_outbound_destination}
  end
end
