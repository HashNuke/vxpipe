defmodule Vxpipe.CallEngine.Error do
  @moduledoc """
  A protocol-neutral failure returned by the call engine.
  """

  @enforce_keys [:code, :message]
  defstruct [:code, :message, retryable: false, details: %{}]

  @type code ::
          :agent_not_ready
          | :agent_busy
          | :call_spec_resolution_failed
          | :call_variables_forbidden
          | :call_variables_revision_conflict
          | :connection_already_attached
          | :connection_not_attached
          | :deadline_exceeded
          | :invalid_call_spec
          | :invalid_call_variables_update
          | :invalid_call_invocation
          | :invalid_command
          | :participant_already_exists
          | :participant_not_found
          | :room_already_exists
          | :room_incarnation_changed
          | :room_not_found
          | :room_start_failed
          | :unsupported_call_plan

  @type t :: %__MODULE__{
          code: code(),
          message: String.t(),
          retryable: boolean(),
          details: %{optional(String.t()) => term()}
        }

  @spec new(code(), String.t(), keyword()) :: t()
  def new(code, message, options \\ []) do
    %__MODULE__{
      code: code,
      message: message,
      retryable: Keyword.get(options, :retryable, false),
      details: Keyword.get(options, :details, %{})
    }
  end

  @spec to_public(t()) :: map()
  def to_public(%__MODULE__{} = error) do
    %{
      "code" => Atom.to_string(error.code),
      "message" => error.message,
      "retryable" => error.retryable,
      "details" => error.details
    }
  end
end
