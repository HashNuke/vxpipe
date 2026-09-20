defmodule Vxpipe.CallEngine.SpeechToTextRuntime do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToText.LegacyBridge

  @derive {Inspect, only: [:call_id, :participant_id, :activation_id, :usage_provider]}
  @enforce_keys [
    :provider,
    :provider_private,
    :transport,
    :media_ingress,
    :call_id,
    :participant_id,
    :activation_id,
    :usage_provider
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          provider: {module(), term()},
          provider_private: keyword(),
          transport: {module(), keyword()} | nil,
          media_ingress: keyword(),
          call_id: String.t(),
          participant_id: String.t(),
          activation_id: String.t() | nil,
          usage_provider: Vxpipe.CallEngine.Usage.ProviderContext.t()
        }

  def provider({provider, options} = selected, settings) do
    if function_exported?(provider, :configure, 1) do
      case Keyword.get(settings, :transport) do
        nil -> {:ok, selected, []}
        _configured_transport -> {:error, :unexpected_transport}
      end
    else
      with {transport, transport_options}
           when is_atom(transport) and is_list(transport_options) <-
             Keyword.get(settings, :transport),
           public when is_list(public) <- LegacyBridge.public_options(provider, options) do
        {:ok, {LegacyBridge, public},
         [provider: provider, config: options, transport: {transport, transport_options}]}
      else
        _invalid -> {:error, :invalid_transport}
      end
    end
  end

  def usage_identity(provider, options) do
    cond do
      function_exported?(provider, :configure, 1) ->
        with {:ok, descriptor} <- provider.configure(options) do
          {:ok,
           [
             name: identity_label(descriptor.usage_identity.provider),
             model: identity_label(descriptor.usage_identity.model)
           ]}
        end

      function_exported?(provider, :usage_identity, 1) ->
        case provider.usage_identity(options) do
          identity when is_list(identity) -> {:ok, identity}
          _invalid -> {:error, :invalid_usage_identity}
        end

      true ->
        {:error, :invalid_usage_identity}
    end
  end

  defp identity_label(value) when is_atom(value), do: Atom.to_string(value)
  defp identity_label(value) when is_binary(value), do: value
end
