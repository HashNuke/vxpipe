defmodule Vxpipe.CallEngine.SpeechToTextRuntime do
  @moduledoc false

  alias Vxpipe.Providers.Deepgram.Flux
  alias Vxpipe.Providers.Deepgram.STTSession, as: FluxSession

  @derive {Inspect, only: [:call_id, :participant_id, :activation_id, :usage_provider]}
  @enforce_keys [
    :provider,
    :provider_private,
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
          media_ingress: keyword(),
          call_id: String.t(),
          participant_id: String.t(),
          activation_id: String.t() | nil,
          usage_provider: Vxpipe.CallEngine.Usage.ProviderContext.t()
        }

  def provider({FluxSession, %Flux{} = config}, settings) do
    with nil <- Keyword.get(settings, :transport),
         nil <- Keyword.get(settings, :transport_options),
         wire_module when is_atom(wire_module) <-
           Keyword.get(settings, :wire_module, Vxpipe.Providers.Deepgram.STTSocket),
         wire_options when is_list(wire_options) <- Keyword.get(settings, :wire_options, []),
         true <- Keyword.keyword?(wire_options) do
      public = [model: config.model, encoding: config.encoding, sample_rate: config.sample_rate]

      {:ok, {FluxSession, public},
       [config: config, wire_module: wire_module, wire_options: wire_options]}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def provider({provider, options} = selected, settings) do
    with nil <- Keyword.get(settings, :transport),
         nil <- Keyword.get(settings, :transport_options),
         nil <- Keyword.get(settings, :wire_module),
         nil <- Keyword.get(settings, :wire_options),
         true <- function_exported?(provider, :configure, 1),
         {:ok, _descriptor} <- provider.configure(options) do
      {:ok, selected, []}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def usage_identity(FluxSession, %Flux{} = config) do
    usage_identity(
      FluxSession,
      model: config.model,
      encoding: config.encoding,
      sample_rate: config.sample_rate
    )
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
