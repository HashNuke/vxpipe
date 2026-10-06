defmodule Vxpipe.CallEngine.CallSpec.ConnectionIntent do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.NumberFromVariable
  alias Vxpipe.CallEngine.CallSpecValidation

  @phone_number ~r/\A\+[1-9][0-9]{1,14}\z/

  @enforce_keys [:service, :mode, :admission]
  defstruct @enforce_keys ++ [number: nil, number_from_variable: nil]

  @type t :: %__MODULE__{
          service: :web | String.t(),
          mode: :receive | :dial,
          admission: :start_call | :transfer,
          number: nil | String.t(),
          number_from_variable: nil | NumberFromVariable.t()
        }

  def new(value, path, options \\ []) do
    code = :invalid_call_spec
    message = "The call spec is invalid."

    with {:ok, input} <-
           CallSpecValidation.normalize_map(
             value,
             [:service, :mode, :admission, :number, :number_from_variable],
             code,
             message,
             path
           ),
         {:ok, service_input} <-
           CallSpecValidation.fetch(input, :service, code, message, path),
         {:ok, service} <- service(service_input, code, message, path),
         {:ok, mode_input} <- CallSpecValidation.fetch(input, :mode, code, message, path),
         {:ok, mode} <-
           CallSpecValidation.enum(
             mode_input,
             [receive: "receive", dial: "dial"],
             code,
             message,
             path ++ ["mode"]
           ),
         {:ok, admission} <- admission(input, mode, code, message, path, options),
         {:ok, number, number_from_variable} <-
           destination(input, service, mode, code, message, path) do
      {:ok,
       %__MODULE__{
         service: service,
         mode: mode,
         admission: admission,
         number: number,
         number_from_variable: number_from_variable
       }}
    end
  end

  defp service("web", _code, _message, _path), do: {:ok, :web}

  defp service(value, code, message, path) do
    CallSpecValidation.identifier(value, code, message, path ++ ["service"])
  end

  defp admission(input, :dial, code, message, path, options) do
    expected = if Keyword.get(options, :outgoing_callee?, false), do: :start_call, else: :transfer

    case Map.fetch(input, :admission) do
      :error ->
        {:ok, expected}

      {:ok, value} ->
        CallSpecValidation.enum(
          value,
          [{expected, Atom.to_string(expected)}],
          code,
          message,
          path ++ ["admission"]
        )
    end
  end

  defp admission(input, :receive, code, message, path, _options) do
    with {:ok, value} <- CallSpecValidation.fetch(input, :admission, code, message, path) do
      CallSpecValidation.enum(
        value,
        [start_call: "start_call", transfer: "transfer"],
        code,
        message,
        path ++ ["admission"]
      )
    end
  end

  defp destination(input, :web, :receive, code, message, path) do
    case Enum.find([:number, :number_from_variable], &Map.has_key?(input, &1)) do
      nil ->
        {:ok, nil, nil}

      field ->
        CallSpecValidation.invalid(
          code,
          message,
          path ++ [Atom.to_string(field)],
          "is not supported for web connections"
        )
    end
  end

  defp destination(_input, :web, :dial, code, message, path) do
    CallSpecValidation.invalid(
      code,
      message,
      path ++ ["mode"],
      "dial mode requires a configured telephony service"
    )
  end

  defp destination(input, _service, :receive, code, message, path) do
    if Map.has_key?(input, :number_from_variable) do
      CallSpecValidation.invalid(
        code,
        message,
        path ++ ["number_from_variable"],
        "is only supported for dial mode"
      )
    else
      with {:ok, number_input} <- CallSpecValidation.fetch(input, :number, code, message, path),
           {:ok, number} <- phone_number(number_input, code, message, path ++ ["number"]) do
        {:ok, number, nil}
      end
    end
  end

  defp destination(input, _service, :dial, code, message, path) do
    case {Map.fetch(input, :number), Map.fetch(input, :number_from_variable)} do
      {{:ok, _number}, {:ok, _source}} ->
        CallSpecValidation.invalid(
          code,
          message,
          path ++ ["number_from_variable"],
          "must not be combined with number"
        )

      {:error, :error} ->
        CallSpecValidation.invalid(
          code,
          message,
          path ++ ["number"],
          "or number_from_variable is required for dial mode"
        )

      {{:ok, number_input}, :error} ->
        with {:ok, number} <- phone_number(number_input, code, message, path ++ ["number"]) do
          {:ok, number, nil}
        end

      {:error, {:ok, source_input}} ->
        with {:ok, source} <-
               NumberFromVariable.new(source_input, path ++ ["number_from_variable"]) do
          {:ok, nil, source}
        end
    end
  end

  defp phone_number(value, code, message, path) when is_binary(value) do
    if Regex.match?(@phone_number, value) do
      {:ok, value}
    else
      CallSpecValidation.invalid(code, message, path, "must be an E.164 telephone number")
    end
  end

  defp phone_number(_value, code, message, path) do
    CallSpecValidation.invalid(code, message, path, "must be an E.164 telephone number")
  end
end
