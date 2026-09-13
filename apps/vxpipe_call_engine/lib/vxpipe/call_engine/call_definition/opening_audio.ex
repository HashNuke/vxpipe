defmodule Vxpipe.CallEngine.CallDefinition.OpeningAudio do
  @moduledoc """
  A validated source for audio played before participant media is admitted.

  The custom inspection keeps configured text and URLs out of routine process logs.
  """

  alias Vxpipe.CallEngine.DefinitionValidation

  @derive {Inspect, only: [:type]}
  @enforce_keys [:type]
  defstruct [:type, :text, :url, :text_to_speech]

  @type t ::
          %__MODULE__{type: :text, text: String.t(), url: nil, text_to_speech: String.t()}
          | %__MODULE__{type: :file_url, text: nil, url: String.t(), text_to_speech: nil}

  @code :invalid_call_definition
  @message "The call definition is invalid."
  @path ["opening_audio"]

  @spec new(nil | map()) :: {:ok, nil | t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def new(nil), do: {:ok, nil}

  def new(value) do
    with {:ok, input} <-
           DefinitionValidation.normalize_map(
             value,
             [:type, :text, :url, :text_to_speech],
             @code,
             @message,
             @path
           ),
         {:ok, type_input} <-
           DefinitionValidation.fetch(input, :type, @code, @message, @path),
         {:ok, type} <-
           DefinitionValidation.enum(
             type_input,
             [text: "text", file_url: "file_url"],
             @code,
             @message,
             @path ++ ["type"]
           ) do
      build(type, input)
    end
  end

  defp build(:text, input) do
    with :ok <- reject_present(input, :url),
         {:ok, text_input} <-
           DefinitionValidation.fetch(input, :text, @code, @message, @path),
         {:ok, text} <-
           DefinitionValidation.string(
             text_input,
             @code,
             @message,
             @path ++ ["text"],
             maximum: 4_096
           ),
         {:ok, profile_input} <-
           DefinitionValidation.fetch(input, :text_to_speech, @code, @message, @path),
         {:ok, profile} <-
           DefinitionValidation.string(
             profile_input,
             @code,
             @message,
             @path ++ ["text_to_speech"],
             maximum: 128
           ) do
      {:ok, %__MODULE__{type: :text, text: text, url: nil, text_to_speech: profile}}
    end
  end

  defp build(:file_url, input) do
    with :ok <- reject_present(input, :text),
         :ok <- reject_present(input, :text_to_speech),
         {:ok, url_input} <-
           DefinitionValidation.fetch(input, :url, @code, @message, @path),
         {:ok, url} <- valid_https_url(url_input) do
      {:ok, %__MODULE__{type: :file_url, text: nil, url: url}}
    end
  end

  defp reject_present(input, key) do
    if Map.has_key?(input, key) do
      invalid([Atom.to_string(key)], "is not supported for this opening audio type")
    else
      :ok
    end
  end

  defp valid_https_url(value) do
    with {:ok, url} <-
           DefinitionValidation.string(
             value,
             @code,
             @message,
             @path ++ ["url"],
             maximum: 2_048
           ),
         %URI{scheme: "https", host: host, userinfo: nil, fragment: nil} when is_binary(host) <-
           URI.parse(url),
         true <- String.trim(host) != "" do
      {:ok, url}
    else
      _invalid -> invalid(["url"], "must be an HTTPS URL without credentials or a fragment")
    end
  end

  defp invalid(relative_path, reason) do
    DefinitionValidation.invalid(@code, @message, @path ++ relative_path, reason)
  end
end
