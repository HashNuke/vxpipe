defmodule Vxpipe.Calls.CallAdmissionBinding do
  @moduledoc "Binds existing admission ownership to one runtime incarnation without starting it."

  alias Vxpipe.Calls.{AdmissionClaim, PreparedCall, Repositories, TelephonyAdmissionClaim}

  def bind(subject, incarnation, options) when is_list(options) do
    with {:ok, call} <- subject_call(subject),
         true <- valid_identifier?(incarnation, 128) and valid_call?(call) do
      persist(subject, call, incarnation, options)
    else
      _invalid -> {:error, :invalid_call_admission}
    end
  end

  def bind(_subject, _incarnation, _options), do: {:error, :invalid_call_admission}

  defp persist(subject, expected, incarnation, options) do
    with {:ok, repository} <- Repositories.fetch(options, :call_repository) do
      case Repositories.call(repository, :bind_call_admission, [subject, incarnation]) do
        {:ok, decision, updated} when decision in [:admit, :cancel] ->
          validate_result(subject, expected, incarnation, decision, updated)

        {:error, reason}
        when reason in [
               :not_found,
               :call_admission_mismatch,
               :call_incarnation_mismatch,
               :admission_not_found,
               :telephony_leg_not_found,
               :telephony_leg_conflict,
               :telephony_service_mismatch
             ] ->
          {:error, reason}

        _unavailable ->
          {:error, :call_admission_unavailable}
      end
    else
      _unavailable -> {:error, :call_admission_unavailable}
    end
  rescue
    _error -> {:error, :call_admission_unavailable}
  catch
    _kind, _reason -> {:error, :call_admission_unavailable}
  end

  defp validate_result(subject, expected, incarnation, decision, updated) do
    with {:ok, call} <- subject_call(updated),
         true <- updated.__struct__ == subject.__struct__,
         true <- call.id == expected.id and call.tenant_key == expected.tenant_key,
         true <- call.room_id == expected.room_id and call.incarnation_id == incarnation do
      {:ok, decision, updated}
    else
      _invalid -> {:error, :call_admission_unavailable}
    end
  end

  defp subject_call(%AdmissionClaim{call: %PreparedCall{} = call}), do: {:ok, call}
  defp subject_call(%TelephonyAdmissionClaim{call: %PreparedCall{} = call}), do: {:ok, call}
  defp subject_call(%PreparedCall{plan: %{direction: :outgoing}} = call), do: {:ok, call}
  defp subject_call(_subject), do: :error

  defp valid_call?(call),
    do:
      valid_identifier?(call.id, 256) and valid_identifier?(call.tenant_key, 256) and
        valid_identifier?(call.room_id, 256) and is_binary(call.plan_digest) and
        byte_size(call.plan_digest) == 32

  defp valid_identifier?(value, maximum) when is_binary(value),
    do:
      byte_size(value) in 1..maximum and String.valid?(value) and
        not String.contains?(value, [<<0>>, "\n", "\r"])

  defp valid_identifier?(_value, _maximum), do: false
end
