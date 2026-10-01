defmodule Vxpipe.CallEngine.SpeechToTextRuntime do
  @moduledoc false

  alias Vxpipe.Providers.Deepgram.Flux
  alias Vxpipe.Providers.Deepgram.STTSession, as: FluxSession
  alias Vxpipe.Providers.Google.STT, as: GoogleSTT
  alias Vxpipe.Providers.Google.STTSession, as: GoogleSTTSession
  alias Vxpipe.Providers.Cartesia.STT, as: CartesiaSTT
  alias Vxpipe.Providers.Cartesia.STTSession, as: CartesiaSTTSession
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}

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
  defstruct @enforce_keys ++ [activity_agent_id: nil]

  @type t :: %__MODULE__{
          provider: {module(), term()},
          provider_private: keyword(),
          media_ingress: keyword(),
          call_id: String.t(),
          participant_id: String.t(),
          activation_id: String.t() | nil,
          usage_provider: Vxpipe.CallEngine.Usage.ProviderContext.t(),
          activity_agent_id: String.t() | nil
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

  def provider({GoogleSTTSession, %GoogleSTT{} = config}, settings) do
    with nil <- Keyword.get(settings, :transport),
         nil <- Keyword.get(settings, :transport_options),
         wire_module when is_atom(wire_module) <-
           Keyword.get(settings, :wire_module, Vxpipe.Providers.Google.STTSocket),
         wire_options when is_list(wire_options) <- Keyword.get(settings, :wire_options, []),
         true <- Keyword.keyword?(wire_options) do
      public = [model: config.model, encoding: config.encoding, sample_rate: config.sample_rate]

      {:ok, {GoogleSTTSession, public},
       [config: config, wire_module: wire_module, wire_options: wire_options]}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def provider({CartesiaSTTSession, %CartesiaSTT{} = config}, settings) do
    with nil <- Keyword.get(settings, :transport),
         nil <- Keyword.get(settings, :transport_options),
         wire_module when is_atom(wire_module) <-
           Keyword.get(settings, :wire_module, Vxpipe.Providers.Cartesia.STTSocket),
         wire_options when is_list(wire_options) <- Keyword.get(settings, :wire_options, []),
         true <- Keyword.keyword?(wire_options) do
      public = [model: config.model, encoding: config.encoding, sample_rate: config.sample_rate]

      {:ok, {CartesiaSTTSession, public},
       [config: config, wire_module: wire_module, wire_options: wire_options]}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def provider({STTSession, %Scribe{} = config}, settings) do
    with nil <- Keyword.get(settings, :transport),
         nil <- Keyword.get(settings, :transport_options),
         wire_module when is_atom(wire_module) and not is_nil(wire_module) <-
           Keyword.get(settings, :wire_module, Vxpipe.Providers.ElevenLabs.ScribeSocket),
         wire_options when is_list(wire_options) <- Keyword.get(settings, :wire_options, []),
         activity_options when is_list(activity_options) <-
           Keyword.get(settings, :activity_options, []),
         true <- Keyword.keyword?(wire_options) and Keyword.keyword?(activity_options) do
      {:ok, {STTSession, scribe_options(config)},
       [
         config: config,
         wire_module: wire_module,
         wire_options: wire_options,
         activity_options: activity_options
       ]}
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

  def usage_identity(GoogleSTTSession, %GoogleSTT{} = config) do
    usage_identity(GoogleSTTSession,
      model: config.model,
      encoding: config.encoding,
      sample_rate: config.sample_rate
    )
  end

  def usage_identity(CartesiaSTTSession, %CartesiaSTT{} = config) do
    usage_identity(CartesiaSTTSession,
      model: config.model,
      encoding: config.encoding,
      sample_rate: config.sample_rate
    )
  end

  def usage_identity(STTSession, %Scribe{} = config),
    do: usage_identity(STTSession, scribe_options(config))

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

  defp scribe_options(config) do
    [
      model: config.model,
      encoding: config.encoding,
      sample_rate: config.sample_rate,
      language_code: config.language_code,
      commit_strategy: config.commit_strategy
    ]
  end
end
