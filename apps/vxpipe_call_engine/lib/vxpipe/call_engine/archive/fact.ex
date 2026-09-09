defmodule Vxpipe.CallEngine.Archive.Fact do
  @moduledoc "A private, protocol-neutral fact accepted from one live room incarnation."

  alias Vxpipe.CallEngine.Archive.Sanitizer

  @derive {Inspect, except: [:payload]}
  @enforce_keys [
    :id,
    :kind,
    :sequence,
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :occurred_at,
    :source_policy,
    :payload
  ]
  defstruct @enforce_keys ++
              [
                :participant_id,
                :activation_id,
                :source_participant_id,
                :connection_id,
                :command_id,
                :correlation_id,
                :tool_call_id,
                :public_sequence
              ]

  @type t :: %__MODULE__{
          id: String.t(),
          kind: atom(),
          sequence: pos_integer(),
          tenant_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t() | nil,
          activation_id: String.t() | nil,
          source_participant_id: String.t() | nil,
          connection_id: String.t() | nil,
          command_id: String.t() | nil,
          correlation_id: String.t() | nil,
          tool_call_id: String.t() | nil,
          public_sequence: pos_integer() | nil,
          occurred_at: DateTime.t(),
          source_policy: map(),
          payload: JSON.t()
        }

  @doc false
  @spec new!(keyword()) :: t()
  def new!(options) when is_list(options) do
    struct!(__MODULE__,
      id: Keyword.fetch!(options, :id),
      kind: Keyword.fetch!(options, :kind),
      sequence: Keyword.fetch!(options, :sequence),
      tenant_id: Keyword.fetch!(options, :tenant_id),
      call_id: Keyword.fetch!(options, :call_id),
      room_id: Keyword.fetch!(options, :room_id),
      incarnation_id: Keyword.fetch!(options, :incarnation_id),
      participant_id: Keyword.get(options, :participant_id),
      activation_id: Keyword.get(options, :activation_id),
      source_participant_id: Keyword.get(options, :source_participant_id),
      connection_id: Keyword.get(options, :connection_id),
      command_id: Keyword.get(options, :command_id),
      correlation_id: Keyword.get(options, :correlation_id),
      tool_call_id: Keyword.get(options, :tool_call_id),
      public_sequence: Keyword.get(options, :public_sequence),
      occurred_at: Keyword.fetch!(options, :occurred_at),
      source_policy: options |> Keyword.fetch!(:source_policy) |> Sanitizer.sanitize(),
      payload: options |> Keyword.get(:payload, %{}) |> Sanitizer.sanitize()
    )
  end
end
