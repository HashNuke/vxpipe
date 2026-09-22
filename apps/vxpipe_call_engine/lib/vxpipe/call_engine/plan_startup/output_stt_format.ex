defmodule Vxpipe.CallEngine.PlanStartup.OutputSTTFormat do
  @moduledoc false

  alias Vxpipe.CallEngine.CapabilityCatalog
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.Speech.Descriptor

  def validate_participant(participant) do
    case validate(
           participant.capabilities.speech_to_speech,
           participant.capabilities.output_speech_to_text
         ) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         Error.new(
           :unsupported_call_plan,
           "The resolved call plan is not supported by this runtime.",
           details: %{
             "path" => [
               "participants",
               participant.call_spec_key,
               "capabilities",
               "output_speech_to_text"
             ],
             "reason" => failure_reason(reason)
           }
         )}
    end
  end

  defp failure_reason(:unsupported_finite_input),
    do: "output recognition requires explicit finite-input completion support"

  defp failure_reason(_reason),
    do: "output recognition requires matching speech formats; conversion is not supported"

  def validate(_generator, nil), do: :ok

  def validate(%CapabilitySelection{} = generator, %CapabilitySelection{} = recognizer) do
    with {:ok, output} <- descriptor(generator),
         {:ok, input} <- descriptor(recognizer),
         :ok <- finite_input(recognizer, input) do
      validate_descriptors(output, input)
    else
      {:error, :unsupported_finite_input} = error -> error
      _invalid -> {:error, :incompatible_output_stt_format}
    end
  rescue
    _exception -> {:error, :incompatible_output_stt_format}
  end

  def validate(_generator, _recognizer), do: {:error, :incompatible_output_stt_format}

  def validate_descriptors(
        %Descriptor{kind: :sts} = generator,
        %Descriptor{kind: :stt} = recognizer
      ) do
    with :ok <- Descriptor.validate(generator),
         :ok <- Descriptor.validate(recognizer),
         true <- generator.format == recognizer.format do
      :ok
    else
      _invalid -> {:error, :incompatible_output_stt_format}
    end
  end

  def validate_descriptors(_generator, _recognizer),
    do: {:error, :incompatible_output_stt_format}

  defp finite_input(selection, %Descriptor{finite_input?: true}) do
    with {:ok, provider} <- CapabilityCatalog.adapter(selection),
         true <- function_exported?(provider, :finish_input, 1) do
      :ok
    else
      _ -> {:error, :unsupported_finite_input}
    end
  end

  defp finite_input(_selection, _descriptor), do: {:error, :unsupported_finite_input}

  # configure/1 is the existing pure public-metadata boundary: no credential
  # lookup, private config, session allocation or audio conversion belongs here.
  defp descriptor(selection) do
    with {:ok, provider} <- CapabilityCatalog.adapter(selection),
         {:ok, options} <- CapabilityCatalog.speech_options(selection) do
      provider.configure(options)
    end
  end
end
