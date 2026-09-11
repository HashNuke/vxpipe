defmodule Vxpipe.Gateway.Telephony.OutgoingLegLifecycle do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Adapter, EndLeg, Event, LegReference}
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, MediaBinding}

  @type action :: {:keep, :ok | {:error, :telephony_leg_mismatch}} | {:stop, :ok}

  @spec end_attempt(MediaBinding.t(), ConfiguredService.t(), String.t(), atom()) :: :ok
  def end_attempt(
        %MediaBinding{} = binding,
        %ConfiguredService{} = service,
        leg_id,
        reason
      )
      when is_binary(leg_id) and is_atom(reason) do
    _result =
      Adapter.end_leg(
        service.adapter,
        service.adapter_options,
        %EndLeg{
          leg: %LegReference{
            leg_id: leg_id,
            provider_call_control_id: binding.provider_call_control_id
          },
          reason: reason
        }
      )

    :ok
  end

  @spec handle(Event.t(), MediaBinding.t(), ConfiguredService.t(), String.t()) :: action()
  def handle(
        %Event{} = event,
        %MediaBinding{} = binding,
        %ConfiguredService{} = service,
        leg_id
      )
      when is_binary(leg_id) do
    if MediaBinding.matches_event?(binding, event) do
      action(event, binding, service, leg_id)
    else
      {:keep, {:error, :telephony_leg_mismatch}}
    end
  end

  defp action(%Event{kind: :answered}, _binding, _service, _leg_id), do: {:keep, :ok}

  defp action(
         %Event{kind: :answering_machine, answering_machine: :machine},
         binding,
         %ConfiguredService{answering_machine_detection: :detect} = service,
         leg_id
       ) do
    :ok = end_attempt(binding, service, leg_id, :answering_machine)
    {:stop, :ok}
  end

  defp action(%Event{kind: :answering_machine}, _binding, _service, _leg_id),
    do: {:keep, :ok}

  defp action(%Event{kind: :ended}, _binding, _service, _leg_id), do: {:stop, :ok}
end
