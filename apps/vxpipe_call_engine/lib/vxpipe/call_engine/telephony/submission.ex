defmodule Vxpipe.CallEngine.Telephony.Submission do
  @moduledoc "The provider-neutral immediate outcome of an asynchronous call-control command."

  @enforce_keys [:status, :provider_call_control_id]
  defstruct @enforce_keys ++ [provider_call_leg_id: nil, provider_call_session_id: nil]

  @type t :: %__MODULE__{
          status: :accepted | :unknown,
          provider_call_control_id: nil | String.t(),
          provider_call_leg_id: nil | String.t(),
          provider_call_session_id: nil | String.t()
        }

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{status: :accepted, provider_call_control_id: identifier} = submission),
    do: present?(identifier) and optional_identifiers_valid?(submission)

  def valid?(%__MODULE__{status: :unknown, provider_call_control_id: identifier} = submission),
    do: (is_nil(identifier) or present?(identifier)) and optional_identifiers_valid?(submission)

  def valid?(%__MODULE__{}), do: false

  defp optional_identifiers_valid?(submission) do
    optional_identifier?(submission.provider_call_leg_id) and
      optional_identifier?(submission.provider_call_session_id)
  end

  defp optional_identifier?(nil), do: true
  defp optional_identifier?(value), do: present?(value)

  defp present?(value), do: is_binary(value) and value != ""
end
