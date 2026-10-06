defmodule Vxpipe.Gateway.OutgoingCallAdmission do
  @moduledoc false

  alias Vxpipe.CallEngine
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{PreparedCall, TelephonyPlanBindings}
  alias Vxpipe.Gateway.CallAdmission.CallEngineOptions
  alias Vxpipe.Gateway.Telephony.ServiceRegistry

  def authenticate(options, tenant, secret),
    do: Calls.authenticate(tenant, secret, :calls, options)

  def claim(options, principal, specification, variables, key),
    do: Calls.claim_outgoing_call(principal, specification, variables, key, options)

  def start(options, %PreparedCall{state: :admitting, plan: %{direction: :outgoing}} = call) do
    token = make_ref()

    runtime =
      options |> CallEngineOptions.build() |> Keyword.put(:outgoing_admission, {self(), token})

    result =
      with :ok <- validate_plan(call.plan, options),
           do: CallEngine.start_call(call.plan, runtime)

    case result do
      {:ok, room} -> start_room(options, call, room, token)
      {:error, _reason} -> fail(options, call, :room_start_failed)
    end
  end

  def start(_options, _call), do: {:error, :invalid_outgoing_call}

  defp start_room(options, call, room, token) do
    case CallEngine.monitor_room(call.tenant_key, call.room_id, room.incarnation_id) do
      {:ok, monitor} ->
        result =
          with {:ok, started} <-
                 Calls.mark_outgoing_call_started(
                   call,
                   room.incarnation_id,
                   DateTime.utc_now(),
                   options
                 ),
               :ok <-
                 CallEngine.admit_outgoing_call(
                   call.tenant_key,
                   call.room_id,
                   room.incarnation_id,
                   token
                 ),
               do: await_submission(options, started, monitor, token)

        Process.demonitor(monitor, [:flush])

        case result do
          {:ok, _call} = success ->
            success

          {:error, reason} ->
            CallEngine.cancel_outgoing_admission(
              call.tenant_key,
              call.room_id,
              room.incarnation_id,
              token
            )

            fail(
              options,
              call,
              if(reason == :startup_unknown, do: :startup_unknown, else: :room_start_failed)
            )
        end

      {:error, _unavailable} ->
        fail(options, call, :room_start_failed)
    end
  end

  defp await_submission(options, call, monitor, token) do
    timeout = Keyword.get(options, :outgoing_start_timeout_ms, 35_000 + call.plan.ring_timeout_ms)

    receive do
      {:vxpipe_outgoing_submission, ^token, {:ok, status}} when status in [:accepted, :unknown] ->
        case Calls.fetch_call(call.tenant_key, call.id, options) do
          {:ok, current} -> {:ok, current}
          {:error, _unavailable} -> {:ok, call}
        end

      {:vxpipe_outgoing_submission, ^token, {:error, _failure}} ->
        {:error, :room_start_failed}

      {:DOWN, ^monitor, :process, _room, {:shutdown, {:outgoing_call, :no_answer}}} ->
        {:error, :startup_unknown}

      {:DOWN, ^monitor, :process, _room, _reason} ->
        {:error, :room_start_failed}
    after
      timeout -> {:error, :startup_unknown}
    end
  end

  defp fail(options, call, reason) do
    _projection = Calls.mark_outgoing_call_failed(call, reason, options)

    {:error,
     if(reason == :startup_unknown,
       do: :outgoing_submission_unknown,
       else: :outgoing_call_start_failed
     )}
  end

  defp validate_plan(plan, options) do
    options =
      case Keyword.get(options, :service_registry) do
        %ServiceRegistry{} = registry -> Keyword.merge(options, registry.repository_options)
        _missing -> options
      end

    TelephonyPlanBindings.with_active(plan, options, fn -> :ok end)
  end
end
