defmodule Vxpipe.AgentRuntime.Event do
  @moduledoc "A normalized, payload-safe runtime lifecycle event."

  @enforce_keys [:kind, :correlation, :data]
  defstruct @enforce_keys

  @type kind :: :request_started | :response_completed | :request_failed | :request_cancelled
  @type t :: %__MODULE__{kind: kind(), correlation: map(), data: map()}

  @spec new(kind(), map(), map()) :: t()
  def new(kind, correlation, data \\ %{})
      when kind in [:request_started, :response_completed, :request_failed, :request_cancelled] and
             is_map(correlation) and is_map(data) do
    %__MODULE__{kind: kind, correlation: correlation, data: data}
  end
end
