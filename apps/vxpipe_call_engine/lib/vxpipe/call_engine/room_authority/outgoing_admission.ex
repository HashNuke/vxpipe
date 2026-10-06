defmodule Vxpipe.CallEngine.RoomAuthority.OutgoingAdmission do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.RoomAuthority.Startup

  @derive {Inspect, only: [:status]}
  defstruct [:status, :owner, :token, :monitor, :plan, :options]

  def start_entries(source, options, state) do
    case {source, Keyword.get(options, :outgoing_admission)} do
      {%ResolvedCallPlan{direction: :outgoing} = plan, {owner, token}}
      when is_pid(owner) and is_reference(token) ->
        pending = %__MODULE__{
          status: :pending,
          owner: owner,
          token: token,
          monitor: Process.monitor(owner),
          plan: plan,
          options: options
        }

        {:ok, %{state | outgoing_admission: pending}}

      {_source, nil} ->
        Startup.start_entries(source, options, state)

      _invalid ->
        {:error, :invalid_outgoing_admission}
    end
  end

  def admit(
        incarnation,
        token,
        {owner, _tag},
        %{outgoing_admission: %__MODULE__{} = admission} = state
      )
      when incarnation == state.snapshot.incarnation_id and token == admission.token and
             owner == admission.owner do
    case admission.status do
      :pending ->
        Process.demonitor(admission.monitor, [:flush])

        state = %{
          state
          | outgoing_admission: %{
              admission
              | status: :released,
                monitor: nil,
                plan: nil,
                options: nil
            }
        }

        case Startup.start_entries(admission.plan, admission.options, state) do
          {:ok, state} -> {:reply, :ok, state}
          {:error, reason} -> {:stop, reason, {:error, :outgoing_start_failed}, state}
        end

      _released ->
        {:reply, :ok, state}
    end
  end

  def admit(_incarnation, _token, _from, state),
    do: {:reply, {:error, :outgoing_admission_mismatch}, state}

  def cancel(
        incarnation,
        token,
        {owner, _tag},
        %{outgoing_admission: %__MODULE__{} = admission} = state
      )
      when incarnation == state.snapshot.incarnation_id and token == admission.token and
             owner == admission.owner,
      do: {:stop, {:shutdown, :outgoing_admission_cancelled}, :ok, state}

  def cancel(_incarnation, _token, _from, state),
    do: {:reply, {:error, :outgoing_admission_mismatch}, state}

  def acknowledge(
        %{outgoing_admission: %__MODULE__{status: :released} = admission} = state,
        result
      ) do
    send(admission.owner, {:vxpipe_outgoing_submission, admission.token, result})
    %{state | outgoing_admission: %{admission | status: :acknowledged}}
  end

  def acknowledge(state, _result), do: state

  def pending?(%{outgoing_admission: %__MODULE__{status: :pending}}), do: true
  def pending?(_state), do: false
end
