defmodule Vxpipe.CallEngine.SpeechToSpeechRuntime do
  @moduledoc "Resolved agent speech-to-speech provider with private credential material."

  alias Vxpipe.CallEngine.Usage.ProviderContext
  alias Vxpipe.CallEngine.PlanStartup.SpeechToSpeechActivation
  alias Vxpipe.Providers.Google.{STS, STSSession}

  @derive {Inspect, only: [:call_id, :participant_id, :activation_id, :usage_provider]}
  @enforce_keys [
    :provider,
    :provider_private,
    :call_id,
    :participant_id,
    :activation_id,
    :usage_provider
  ]
  defstruct @enforce_keys ++ [output_speech_to_text: nil]

  @type t :: %__MODULE__{
          provider: {module(), keyword()},
          provider_private: keyword(),
          call_id: String.t(),
          participant_id: String.t(),
          activation_id: String.t() | nil,
          usage_provider: ProviderContext.t(),
          output_speech_to_text: nil | {module(), keyword()}
        }

  def configure(STSSession, options) do
    with {:ok, _config} <- STS.new(options), do: {:ok, options}
  end

  def configure(provider, options) do
    with {:ok, _descriptor} <- provider.configure(options), do: {:ok, options}
  end

  def provider({provider, options} = selected, settings) do
    with nil <- Keyword.get(settings, :transport),
         nil <- Keyword.get(settings, :transport_options),
         nil <- Keyword.get(settings, :wire_module),
         nil <- Keyword.get(settings, :wire_options),
         true <- Code.ensure_loaded?(provider),
         true <- function_exported?(provider, :configure, 1),
         {:ok, _descriptor} <- provider.configure(options) do
      {:ok, selected, []}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def provider({STSSession, options}, settings, %SpeechToSpeechActivation{} = activation) do
    tools =
      Enum.map(activation.tools, fn tool ->
        %{
          "name" => tool.name,
          "description" => tool.description,
          "parametersJsonSchema" => tool.input_schema
        }
      end)

    with true <- Keyword.keyword?(options),
         false <- Keyword.has_key?(options, :system_prompt) or Keyword.has_key?(options, :tools),
         {:ok, config} <-
           STS.new(options ++ [system_prompt: activation.system_prompt, tools: tools]),
         public = [model: config.model, voice: config.voice, turn_control: config.turn_control],
         {:ok, selected, []} <- provider({STSSession, public}, settings) do
      {:ok, selected, [config: config]}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  rescue
    _exception -> {:error, :invalid_configuration}
  end

  def provider(selected, settings, %SpeechToSpeechActivation{} = activation) do
    with {:ok, selected, private} <- provider(selected, settings) do
      {:ok, selected, Keyword.put(private, :activation, activation)}
    end
  end

  def usage_identity(provider, options) do
    with true <- Code.ensure_loaded?(provider),
         true <- function_exported?(provider, :configure, 1),
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
