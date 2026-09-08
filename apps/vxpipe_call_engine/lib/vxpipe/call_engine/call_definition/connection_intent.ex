defmodule Vxpipe.CallEngine.CallDefinition.ConnectionIntent do
  @moduledoc false

  alias Vxpipe.CallEngine.DefinitionValidation

  @enforce_keys [:service, :mode, :admission]
  defstruct @enforce_keys

  @type t :: %__MODULE__{service: :web, mode: :receive, admission: :start_call}

  def new(value, path) do
    code = :invalid_call_definition
    message = "The call definition is invalid."

    with {:ok, input} <-
           DefinitionValidation.normalize_map(
             value,
             [:service, :mode, :admission],
             code,
             message,
             path
           ),
         {:ok, service_input} <-
           DefinitionValidation.fetch(input, :service, code, message, path),
         {:ok, service} <-
           DefinitionValidation.enum(
             service_input,
             [web: "web"],
             code,
             message,
             path ++ ["service"]
           ),
         {:ok, mode_input} <- DefinitionValidation.fetch(input, :mode, code, message, path),
         {:ok, mode} <-
           DefinitionValidation.enum(
             mode_input,
             [receive: "receive"],
             code,
             message,
             path ++ ["mode"]
           ),
         {:ok, admission_input} <-
           DefinitionValidation.fetch(input, :admission, code, message, path),
         {:ok, admission} <-
           DefinitionValidation.enum(
             admission_input,
             [start_call: "start_call"],
             code,
             message,
             path ++ ["admission"]
           ) do
      {:ok, %__MODULE__{service: service, mode: mode, admission: admission}}
    end
  end
end
