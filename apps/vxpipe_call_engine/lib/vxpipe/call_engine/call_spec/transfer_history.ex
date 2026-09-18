defmodule Vxpipe.CallEngine.CallSpec.TransferHistory do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpecValidation

  @enforce_keys [:mode, :turns]
  defstruct @enforce_keys

  @type mode :: :fresh | :all_spoken | :last_n_spoken | :selected
  @type t :: %__MODULE__{mode: mode(), turns: nil | pos_integer()}

  @spec new(nil | map(), [String.t()]) ::
          {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def new(value, path)

  def new(nil, _path), do: {:ok, %__MODULE__{mode: :fresh, turns: nil}}

  def new(value, path) when is_map(value) do
    code = :invalid_call_spec
    message = "The call spec is invalid."

    with {:ok, input} <-
           CallSpecValidation.normalize_map(value, [:mode, :turns], code, message, path),
         {:ok, mode_input} <- CallSpecValidation.fetch(input, :mode, code, message, path),
         {:ok, mode} <-
           CallSpecValidation.enum(
             mode_input,
             [
               fresh: "fresh",
               all_spoken: "all_spoken",
               last_n_spoken: "last_n_spoken",
               selected: "selected"
             ],
             code,
             message,
             path ++ ["mode"]
           ),
         {:ok, turns} <- turns(mode, input, code, message, path) do
      {:ok, %__MODULE__{mode: mode, turns: turns}}
    end
  end

  def new(_value, path) do
    CallSpecValidation.invalid(
      :invalid_call_spec,
      "The call spec is invalid.",
      path,
      "must be an object"
    )
  end

  defp turns(:last_n_spoken, input, code, message, path) do
    with {:ok, value} <- CallSpecValidation.fetch(input, :turns, code, message, path),
         {:ok, turns} <-
           CallSpecValidation.positive_integer(value, code, message, path ++ ["turns"]) do
      {:ok, turns}
    end
  end

  defp turns(_mode, input, code, message, path) do
    if Map.has_key?(input, :turns) do
      CallSpecValidation.invalid(
        code,
        message,
        path ++ ["turns"],
        "is only supported for last_n_spoken mode"
      )
    else
      {:ok, nil}
    end
  end
end
