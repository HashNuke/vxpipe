defmodule Vxpipe.CallEngine.CallInvocation do
  @moduledoc """
  Trusted call identity combined with caller-safe invocation input.
  """

  alias Vxpipe.CallEngine.{DefinitionValidation, Id}

  @fields [:call_definition, :initial_variables, :transport]

  @enforce_keys [
    :tenant_id,
    :actor_id,
    :call_id,
    :room_id,
    :definition_id,
    :definition_revision,
    :initial_variables,
    :transport
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          actor_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          definition_id: String.t(),
          definition_revision: pos_integer(),
          initial_variables: map(),
          transport: :web
        }

  @spec new(map(), keyword()) :: {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def new(value, options) when is_list(options) do
    code = :invalid_call_invocation
    message = "The call invocation is invalid."

    with {:ok, input} <- DefinitionValidation.normalize_map(value, @fields, code, message, []),
         {:ok, tenant_input} <- trusted_option(options, :tenant_id, code, message),
         {:ok, tenant_id} <-
           DefinitionValidation.identifier(tenant_input, code, message, ["tenant_id"]),
         {:ok, actor_input} <- trusted_option(options, :actor_id, code, message),
         {:ok, actor_id} <-
           DefinitionValidation.identifier(actor_input, code, message, ["actor_id"]),
         {:ok, call_id} <- trusted_id(options, :call_id, :call, code, message),
         {:ok, room_id} <- trusted_id(options, :room_id, :room, code, message),
         {:ok, definition_input} <-
           DefinitionValidation.fetch(input, :call_definition, code, message, []),
         {:ok, definition_id, definition_revision} <-
           definition_ref(definition_input, code, message),
         {:ok, initial_variables} <-
           initial_variables(Map.get(input, :initial_variables, %{}), code, message),
         {:ok, transport_input} <-
           DefinitionValidation.fetch(input, :transport, code, message, []),
         {:ok, transport} <- transport(transport_input, code, message) do
      {:ok,
       %__MODULE__{
         tenant_id: tenant_id,
         actor_id: actor_id,
         call_id: call_id,
         room_id: room_id,
         definition_id: definition_id,
         definition_revision: definition_revision,
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
      :error -> DefinitionValidation.invalid(code, message, [Atom.to_string(key)], "is required")
    end
  end

  defp trusted_id(options, key, kind, code, message) do
    value = Keyword.get(options, key, Id.generate(kind))
    DefinitionValidation.identifier(value, code, message, [Atom.to_string(key)])
  end

  defp definition_ref(value, code, message) do
    path = ["call_definition"]

    with {:ok, input} <-
           DefinitionValidation.normalize_map(value, [:id, :revision], code, message, path),
         {:ok, id_input} <- DefinitionValidation.fetch(input, :id, code, message, path),
         {:ok, id} <- DefinitionValidation.identifier(id_input, code, message, path ++ ["id"]),
         {:ok, revision_input} <-
           DefinitionValidation.fetch(input, :revision, code, message, path),
         {:ok, revision} <-
           DefinitionValidation.positive_integer(
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
    DefinitionValidation.invalid(code, message, ["initial_variables"], "must be an object")
  end

  defp transport(value, code, message) do
    path = ["transport"]

    with {:ok, input} <-
           DefinitionValidation.normalize_map(value, [:type], code, message, path),
         {:ok, type_input} <- DefinitionValidation.fetch(input, :type, code, message, path),
         {:ok, type} <-
           DefinitionValidation.enum(type_input, [web: "web"], code, message, path ++ ["type"]) do
      {:ok, type}
    end
  end

  defp invalid(path, reason) do
    DefinitionValidation.invalid(
      :invalid_call_invocation,
      "The call invocation is invalid.",
      path,
      reason
    )
  end
end
