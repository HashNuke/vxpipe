defmodule Vxpipe.Gateway.TestManagedIncomingBackend do
  @moduledoc false
  use Agent

  alias Vxpipe.CallEngine.Telephony.Submission
  alias Vxpipe.Gateway.{CallAdmission, CallCleanupSupervisor, IncomingCallAdmission}
  alias Vxpipe.Gateway.Telephony.IncomingLegActivationResult

  def start_link(options), do: Agent.start_link(fn -> Map.new(options) end)
  def backend(agent), do: {__MODULE__, agent}
  def state(agent), do: Agent.get(agent, & &1)

  def claim_incoming(agent, _identity, _event), do: {:ok, state(agent).claim}

  def start_incoming(agent, claim, _service, owner, token),
    do: IncomingCallAdmission.start(options(agent), claim, owner, token)

  def bind_incoming(agent, claim, incarnation),
    do: CallAdmission.bind_incoming(options(agent), claim, incarnation)

  def bind_call_admission(_agent, claim, incarnation),
    do: {:ok, :admit, %{claim | call: %{claim.call | incarnation_id: incarnation}}}

  def bind_managed_call_admission(agent, claim, incarnation) do
    current = state(agent)

    if Map.get(current, :bind_error?, false) do
      {:error, :call_admission_unavailable}
    else
      updated = %{
        claim
        | call: %{claim.call | incarnation_id: incarnation, gateway_cleanup_required: true}
      }

      Agent.update(agent, &Map.put(&1, :claim, updated))
      send(current.observer, {:managed_reserved, updated})
      {:ok, Map.get(current, :decision, :admit), Map.get(current, :reservation, :new), updated}
    end
  end

  def identify_incoming(agent, service, claim, room, leg) do
    current = state(agent)

    binding = %{
      tenant_key: claim.call.tenant_key,
      call_id: claim.call.id,
      room_id: claim.call.room_id,
      incarnation_id: room.incarnation_id
    }

    send(
      current.observer,
      {:identifying_incoming, leg, binding, CallCleanupSupervisor.lookup(binding)}
    )

    case CallAdmission.identify_incoming(options(agent), service, claim, room, leg) do
      {:ok, identity} ->
        {:ok,
         if(Map.get(current, :nil_usage?, false), do: %{identity | usage: nil}, else: identity)}

      error ->
        error
    end
  end

  def prepare_incoming(agent, identity) do
    send(state(agent).observer, {:preparing_incoming, identity.binding})
    CallAdmission.prepare_incoming(options(agent), identity)
  end

  def submit_incoming(_agent, prepared) do
    {:ok,
     %IncomingLegActivationResult{
       binding: prepared.binding,
       media_url: prepared.media_url,
       service: prepared.service,
       usage: prepared.usage,
       submission: %Submission{
         status: :accepted,
         provider_call_control_id: prepared.binding.provider_call_control_id
       }
     }}
  end

  def cancel_incoming(_agent, claim, token, reason),
    do: IncomingCallAdmission.cancel(claim, token, reason)

  def release_incoming(_agent, claim, token), do: IncomingCallAdmission.release(claim, token)
  def mark_incoming_failed(_agent, claim, _reason), do: {:ok, claim}

  def end_incoming(agent, _service, event, _activation, _reason) do
    current = state(agent)
    send(current.observer, {:incoming_end, self(), event.provider_call_control_id})
    if Map.get(current, :block_end?, false), do: receive(do: (:finish_end -> :ok)), else: :ok
  end

  def handle_live_event(agent, claim, activation, source, event),
    do: CallAdmission.handle_live_event(options(agent), claim, activation, source, event)

  def store_usage_observation(agent, observation) do
    send(state(agent).observer, {:incoming_usage_store, self(), observation})
    receive do: (:store -> {:ok, observation})
  end

  def complete_call_cleanup(agent, binding, completed_at) do
    send(state(agent).observer, {:incoming_cleanup_completed, binding, completed_at})
    {:ok, %{state(agent).claim.call | gateway_cleanup_completed_at: completed_at}}
  end

  defp options(agent) do
    current = state(agent)

    Keyword.merge(current.runtime_options,
      managed_cleanup: true,
      call_repository: {__MODULE__, agent},
      usage_repository: {__MODULE__, agent},
      publication_enabled: false,
      media_admission: current.media_admission,
      telephony_leg_id:
        if(Map.get(current, :identity_failure?, false),
          do: fn -> nil end,
          else: fn -> "managed-incoming-leg" end
        ),
      cleanup_options: [retry_ms: 1]
    )
  end
end
