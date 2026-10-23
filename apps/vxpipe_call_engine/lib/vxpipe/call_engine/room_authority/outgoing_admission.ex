defmodule Vxpipe.CallEngine.RoomAuthority.OutgoingAdmission do
  @moduledoc """
  Owner-monitored startup gate for all resolved calls. The existing internal name
  and state slot also retain outgoing submission acknowledgements and legacy API
  reasons; generic admission uses the same ownership and release checks.
  """

  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.RoomAuthority.Startup

  @derive {Inspect, only: [:status]}
  defstruct [:status, :mode, :owner, :token, :monitor, :plan, :options, outgoing?: false]

  def control({:admit_outgoing, incarnation, token}, from, state),
    do: admit(incarnation, token, from, state)

  def control({:cancel_outgoing, incarnation, token}, from, state),
    do: cancel(incarnation, token, from, state)

  def control({:admit_call, incarnation, token}, from, state),
    do: admit(incarnation, token, from, state, :call)

  def control({:cancel_call_admission, incarnation, token}, from, state),
    do: cancel(incarnation, token, from, state, :call)

  def start_entries(source, options, state) do
    case gate(source, options) do
      {:pending, mode, plan, owner, token} ->
        pending = %__MODULE__{
          status: :pending,
          mode: mode,
          owner: owner,
          token: token,
          monitor: Process.monitor(owner),
          plan: plan,
          options: options,
          outgoing?: plan.direction == :outgoing
        }

        {:ok, %{state | outgoing_admission: pending}}

      :ungated ->
        Startup.start_entries(source, options, state)

      {:error, _reason} = error ->
        error
    end
  end

  defp gate(source, options) do
    case {source, Keyword.get(options, :call_admission),
          Keyword.get(options, :outgoing_admission)} do
      {%ResolvedCallPlan{} = plan, {owner, token}, nil}
      when is_pid(owner) and is_reference(token) ->
        {:pending, :call, plan, owner, token}

      {%ResolvedCallPlan{direction: :outgoing} = plan, nil, {owner, token}}
      when is_pid(owner) and is_reference(token) ->
        {:pending, :outgoing, plan, owner, token}

      {_source, nil, nil} ->
        :ungated

      {_source, nil, _legacy} ->
        {:error, :invalid_outgoing_admission}

      _invalid ->
        {:error, :invalid_call_admission}
    end
  end

  def admit(incarnation, token, from, state, mode \\ :outgoing)

  def admit(
        incarnation,
        token,
        {owner, _tag},
        %{outgoing_admission: %__MODULE__{} = admission} = state,
        mode
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
          {:error, reason} -> {:stop, reason, {:error, start_failed(mode)}, state}
        end

      _released ->
        {:reply, :ok, state}
    end
  end

  def admit(_incarnation, _token, _from, state, mode),
    do: {:reply, {:error, mismatch(mode)}, state}

  def cancel(incarnation, token, from, state, mode \\ :outgoing)

  def cancel(
        incarnation,
        token,
        {owner, _tag},
        %{outgoing_admission: %__MODULE__{} = admission} = state,
        _mode
      )
      when incarnation == state.snapshot.incarnation_id and token == admission.token and
             owner == admission.owner,
      do: {:stop, {:shutdown, cancelled(admission.mode)}, :ok, state}

  def cancel(_incarnation, _token, _from, state, mode),
    do: {:reply, {:error, mismatch(mode)}, state}

  def acknowledge(
        %{outgoing_admission: %__MODULE__{status: :released, outgoing?: true} = admission} = state,
        result
      ) do
    send(admission.owner, {:vxpipe_outgoing_submission, admission.token, result})
    %{state | outgoing_admission: %{admission | status: :acknowledged}}
  end

  def acknowledge(state, _result), do: state

  def abandoned_reason(%{outgoing_admission: %__MODULE__{mode: :call}}),
    do: :call_admission_abandoned

  def abandoned_reason(_state), do: :outgoing_admission_abandoned

  defp mismatch(:call), do: :call_admission_mismatch
  defp mismatch(:outgoing), do: :outgoing_admission_mismatch
  defp start_failed(:call), do: :call_start_failed
  defp start_failed(:outgoing), do: :outgoing_start_failed
  defp cancelled(:call), do: :call_admission_cancelled
  defp cancelled(:outgoing), do: :outgoing_admission_cancelled

  def pending?(%{outgoing_admission: %__MODULE__{status: :pending}}), do: true
  def pending?(_state), do: false
end
