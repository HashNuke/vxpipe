defmodule Vxpipe.CallEngine.TextToSpeechRuntime do
  @moduledoc false

  alias Vxpipe.Providers.Deepgram.FluxTextToSpeech
  alias Vxpipe.Providers.Deepgram.TTSSession, as: FluxSession
  alias Vxpipe.Providers.Rime.{TTS, TTSSession}

  @derive {Inspect, only: [:maximum_requests, :asset_cache_identity]}
  @enforce_keys [
    :provider,
    :provider_private,
    :maximum_requests,
    :asset_cache_identity,
    :call_id,
    :participant_id,
    :activation_id,
    :usage_provider
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          provider: {module(), keyword()},
          provider_private: keyword(),
          maximum_requests: pos_integer(),
          asset_cache_identity: map(),
          call_id: String.t(),
          participant_id: String.t(),
          activation_id: String.t() | nil,
          usage_provider: Vxpipe.CallEngine.Usage.ProviderContext.t()
        }

  def provider({FluxSession, %FluxTextToSpeech{} = config}, settings) do
    with nil <- Keyword.get(settings, :transport),
         nil <- Keyword.get(settings, :transport_options),
         wire_module when is_atom(wire_module) <-
           Keyword.get(
             settings,
             :wire_module,
             Vxpipe.Providers.Deepgram.TTSSocket
           ),
         wire_options when is_list(wire_options) <- Keyword.get(settings, :wire_options, []),
         true <- Keyword.keyword?(wire_options) do
      public = [model: config.model, encoding: config.encoding, sample_rate: config.sample_rate]

      with {:ok, descriptor} <- FluxSession.configure(public) do
        {:ok, {FluxSession, public},
         [config: config, wire_module: wire_module, wire_options: wire_options], descriptor}
      end
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def provider({TTSSession, %TTS{} = config}, settings) do
    with nil <- Keyword.get(settings, :transport),
         nil <- Keyword.get(settings, :transport_options),
         wire_module when is_atom(wire_module) <-
           Keyword.get(settings, :wire_module, Vxpipe.Providers.Rime.TTSSocket),
         wire_options when is_list(wire_options) <- Keyword.get(settings, :wire_options, []),
         true <- Keyword.keyword?(wire_options) do
      public = [model: config.model, speaker: config.speaker, sample_rate: config.sample_rate]

      with {:ok, descriptor} <- TTSSession.configure(public) do
        {:ok, {TTSSession, public},
         [config: config, wire_module: wire_module, wire_options: wire_options], descriptor}
      end
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
         {:ok, descriptor} <- provider.configure(options) do
      {:ok, selected, [], descriptor}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def usage_identity(provider, options) do
    with true <- function_exported?(provider, :configure, 1),
         {:ok, descriptor} <- provider.configure(options) do
      {:ok,
       [
         name: identity_label(descriptor.usage_identity.provider),
         model: identity_label(descriptor.usage_identity.model)
       ]}
    else
      _invalid -> {:error, :invalid_usage_identity}
    end
  end

  defp identity_label(value) when is_atom(value), do: Atom.to_string(value)
  defp identity_label(value) when is_binary(value), do: value
end
