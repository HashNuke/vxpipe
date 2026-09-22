defmodule Vxpipe.CallEngine.CallSpec.CapabilitySelection do
  @moduledoc false

  alias Vxpipe.CallEngine.{CapabilityCatalog, CallSpecValidation}

  @enforce_keys [:kind, :provider, :model, :credential_name, :options, :provider_options]
  defstruct @enforce_keys

  @type kind ::
          :speech_to_text
          | :model_inference
          | :text_to_speech
          | :speech_to_speech
          | :output_speech_to_text

  @type t :: %__MODULE__{
          kind: kind(),
          provider: String.t(),
          model: String.t(),
          credential_name: String.t() | nil,
          options: map(),
          provider_options: map()
        }

  @code :invalid_call_spec
  @message "The call spec is invalid."
  @fields [:provider, :model, :credential_name, :options, :provider_options]

  def new(input, kind, path) do
    with {:ok, input} <- CallSpecValidation.normalize_map(input, @fields, @code, @message, path),
         {:ok, provider} <- required_string(input, :provider, path),
         {:ok, model} <- required_string(input, :model, path),
         {:ok, options} <- json_object(Map.get(input, :options, %{}), path ++ ["options"]),
         {:ok, provider_options} <-
           json_object(Map.get(input, :provider_options, %{}), path ++ ["provider_options"]),
         {:ok, credential_name} <- credential_name(input, provider, path),
         selection <- %__MODULE__{
           kind: kind,
           provider: provider,
           model: model,
           credential_name: credential_name,
           options: options,
           provider_options: provider_options
         },
         :ok <- validate(selection, path) do
      {:ok, selection}
    end
  end

  def validate(%__MODULE__{} = selection, path) do
    with true <- valid_shape?(selection),
         :ok <- CapabilityCatalog.validate(selection) do
      :ok
    else
      _invalid -> invalid(path, "must select a supported provider, model and options")
    end
  end

  defp valid_shape?(selection) do
    MapSet.new(Map.keys(selection)) == MapSet.new([:__struct__ | @enforce_keys]) and
      selection.kind in [
        :speech_to_text,
        :model_inference,
        :text_to_speech,
        :speech_to_speech,
        :output_speech_to_text
      ] and
      is_binary(selection.provider) and is_binary(selection.model) and
      String.valid?(selection.model) and byte_size(selection.model) in 1..256 and
      valid_binding?(selection) and is_map(selection.options) and
      is_map(selection.provider_options) and
      not CallSpecValidation.private_data?(selection.options) and
      not CallSpecValidation.private_data?(selection.provider_options)
  end

  defp valid_binding?(%{provider: provider, credential_name: name})
       when provider in ["fixture", "morse"],
       do: is_nil(name)

  defp valid_binding?(%{credential_name: name}),
    do: is_binary(name) and Regex.match?(~r/\A[A-Za-z0-9_-]{1,128}\z/, name)

  def identity(%__MODULE__{} = selection, tenant_id) do
    {tenant_id, selection}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp required_string(input, key, path) do
    with {:ok, value} <- CallSpecValidation.fetch(input, key, @code, @message, path) do
      CallSpecValidation.string(value, @code, @message, path ++ [Atom.to_string(key)],
        maximum: 256
      )
    end
  end

  defp credential_name(input, provider, path) when provider in ["fixture", "morse"] do
    if Map.has_key?(input, :credential_name),
      do: invalid(path ++ ["credential_name"], "is not supported for a local provider"),
      else: {:ok, nil}
  end

  defp credential_name(input, _provider, path) do
    CallSpecValidation.identifier(
      Map.get(input, :credential_name, "default"),
      @code,
      @message,
      path ++ ["credential_name"]
    )
  end

  defp json_object(%_struct{}, path), do: invalid(path, "must contain only public JSON data")

  defp json_object(value, path) when is_map(value) do
    if CallSpecValidation.private_data?(value) do
      invalid(path, "must contain only public JSON data")
    else
      case value |> JSON.encode!() |> JSON.decode() do
        {:ok, normalized} -> {:ok, normalized}
        _invalid -> invalid(path, "must contain only public JSON data")
      end
    end
  rescue
    _exception -> invalid(path, "must contain only public JSON data")
  end

  defp json_object(_value, path), do: invalid(path, "must be an object")

  defp invalid(path, reason), do: CallSpecValidation.invalid(@code, @message, path, reason)
end
