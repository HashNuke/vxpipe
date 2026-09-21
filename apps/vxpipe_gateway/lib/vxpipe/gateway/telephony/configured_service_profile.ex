defmodule Vxpipe.Gateway.Telephony.ConfiguredServiceProfile do
  @moduledoc false

  alias Vxpipe.Providers.Registry

  @derive {Inspect, only: [:provider, :provider_connection_id, :adapter]}
  @enforce_keys [
    :provider,
    :provider_connection_id,
    :adapter,
    :adapter_options,
    :verifier_options
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          provider: :telnyx | :twilio,
          provider_connection_id: String.t(),
          adapter: module(),
          adapter_options: keyword(),
          verifier_options: keyword()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_telephony_service_configuration}
  def new(options) when is_list(options) do
    case Keyword.get(options, :provider) do
      :telnyx ->
        with {:ok, profile} <- Registry.resolve_capability("telnyx", :telephony) do
          profile.new(options)
        else
          {:error, _reason} -> {:error, :invalid_telephony_service_configuration}
        end

      :twilio ->
        with {:ok, profile} <- Registry.resolve_capability("twilio", :telephony) do
          profile.new(options)
        else
          {:error, _reason} -> {:error, :invalid_telephony_service_configuration}
        end

      _unsupported ->
        {:error, :invalid_telephony_service_configuration}
    end
  end
end
