defmodule Vxpipe.CallEngine.CallInvocation do
  @moduledoc """
  Trusted call identity combined with caller-safe invocation input.
  """

  alias Vxpipe.CallEngine.{CallSpecValidation, Id}

  @fields [:call_spec, :initial_variables, :transport]

  @enforce_keys [
    :tenant_id,
    :actor_id,
    :call_id,
    :room_id,
    :call_spec_id,
    :call_spec_revision,
    :initial_variables,
    :transport
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          actor_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          call_spec_id: String.t(),
          call_spec_revision: pos_integer(),
          initial_variables: map(),
          transport: :web | :telephony
        }

  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def new(value, options) when is_list(options) do
    code = :invalid_call_invocation
    message = "The call invocation is invalid."

    with {:ok, input} <- CallSpecValidation.normalize_map(value, @fields, code, message, []),
         {:ok, tenant_input} <- trusted_option(options, :tenant_id, code, message),
         {:ok, tenant_id} <-
           CallSpecValidation.identifier(tenant_input, code, message, ["tenant_id"]),
         {:ok, actor_input} <- trusted_option(options, :actor_id, code, message),
         {:ok, actor_id} <-
           CallSpecValidation.identifier(actor_input, code, message, ["actor_id"]),
         {:ok, call_id} <- trusted_id(options, :call_id, :call, code, message),
         {:ok, room_id} <- trusted_id(options, :room_id, :room, code, message),
         {:ok, call_spec_input} <-
           CallSpecValidation.fetch(input, :call_spec, code, message, []),
         {:ok, call_spec_id, call_spec_revision} <-
           call_spec_ref(call_spec_input, code, message),
         {:ok, initial_variables} <-
           initial_variables(Map.get(input, :initial_variables, %{}), code, message),
         {:ok, transport_input} <-
           CallSpecValidation.fetch(input, :transport, code, message, []),
         {:ok, transport} <- transport(transport_input, code, message) do
      {:ok,
       %__MODULE__{
         tenant_id: tenant_id,
         actor_id: actor_id,
         call_id: call_id,
         room_id: room_id,
         call_spec_id: call_spec_id,
         call_spec_revision: call_spec_revision,
         initial_variables: initial_variables,
         transport: transport
       }}
    end
  end

  @spec from_json(binary(), keyword()) :: {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def from_json(json, options) when is_binary(json) and is_list(options) do
    case JSON.decode(json) do
      {:ok, value} -> new(value, options)
      {:error, _reason} -> invalid([], "must be valid JSON")
    end
  end

  defp trusted_option(options, key, code, message) do
    case Keyword.fetch(options, key) do
      {:ok, value} -> {:ok, value}
      :error -> CallSpecValidation.invalid(code, message, [Atom.to_string(key)], "is required")
    end
  end

  defp trusted_id(options, key, kind, code, message) do
    value = Keyword.get(options, key, Id.generate(kind))
    CallSpecValidation.identifier(value, code, message, [Atom.to_string(key)])
  end

  defp call_spec_ref(value, code, message) do
    path = ["call_spec"]

    with {:ok, input} <-
           CallSpecValidation.normalize_map(value, [:id, :revision], code, message, path),
         {:ok, id_input} <- CallSpecValidation.fetch(input, :id, code, message, path),
         {:ok, id} <- CallSpecValidation.identifier(id_input, code, message, path ++ ["id"]),
         {:ok, revision_input} <-
           CallSpecValidation.fetch(input, :revision, code, message, path),
         {:ok, revision} <-
           CallSpecValidation.positive_integer(
             revision_input,
             code,
             message,
             path ++ ["revision"]
           ) do
      {:ok, id, revision}
    end
  end

  defp initial_variables(value, _code, _message) when is_map(value), do: {:ok, value}

  defp initial_variables(_value, code, message) do
    CallSpecValidation.invalid(code, message, ["variables"], "must be an object")
  end

  defp transport(value, code, message) do
    path = ["transport"]

    with {:ok, input} <-
           CallSpecValidation.normalize_map(value, [:type], code, message, path),
         {:ok, type_input} <- CallSpecValidation.fetch(input, :type, code, message, path),
         {:ok, type} <-
           CallSpecValidation.enum(
             type_input,
             [web: "web", telephony: "telephony"],
             code,
             message,
             path ++ ["type"]
           ) do
      {:ok, type}
    end
  end

  defp invalid(path, reason) do
    CallSpecValidation.invalid(
      :invalid_call_invocation,
      "The call invocation is invalid.",
      path,
      reason
    )
  end
end
