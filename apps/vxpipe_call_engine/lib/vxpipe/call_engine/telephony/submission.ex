defmodule Vxpipe.CallEngine.Telephony.Submission do
  @moduledoc "The provider-neutral immediate outcome of an asynchronous call-control command."

  @enforce_keys [:status, :provider_call_control_id]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          status: :accepted | :unknown,
          provider_call_control_id: nil | String.t()
        }

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{status: :accepted, provider_call_control_id: identifier}),
    do: present?(identifier)

  def valid?(%__MODULE__{status: :unknown, provider_call_control_id: identifier}),
    do: is_nil(identifier) or present?(identifier)

  def valid?(%__MODULE__{}), do: false

  defp present?(value), do: is_binary(value) and value != ""
end
