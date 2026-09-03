defmodule Vxpipe.CallEngine.Error do
  @moduledoc """
  A protocol-neutral failure returned by the call engine.
  """

  @enforce_keys [:code, :message]
  defstruct [:code, :message, retryable: false, details: %{}]

  @type code ::
          :agent_not_ready
          | :connection_already_attached
          | :connection_not_attached
          | :deadline_exceeded
          | :invalid_command
          | :participant_already_exists
          | :participant_not_found
          | :room_already_exists
          | :room_incarnation_changed
          | :room_not_found
          | :room_start_failed

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
