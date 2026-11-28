defmodule Vxpipe.AgentRuntime.RoundCandidate do
  @moduledoc """
  A tentative model round withheld from public effects until host admission.

  The runtime builds one candidate per model generation, ahead of both the
  text-only and tool-bearing branches. Streamed text is buffered under the
  session byte/turn bounds; proposed calls are permitted structured evidence.
  """

  alias Vxpipe.AgentRuntime.{Dialogue, ToolCall}

  @enforce_keys [
    :text,
    :tool_calls,
    :speech?,
    :tool_only?,
    :correlation,
    :attempt,
    :maximum_bytes
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          text: String.t(),
          tool_calls: [ToolCall.t()],
          speech?: boolean(),
          tool_only?: boolean(),
          correlation: map(),
          attempt: pos_integer(),
          maximum_bytes: pos_integer()
        }

  @spec new(String.t(), keyword()) :: t()
  def new(text, options) when is_binary(text) and is_list(options) do
    with {:ok, options} <-
           Keyword.validate(options, [
             :tool_calls,
             :correlation,
             :attempt,
             :maximum_bytes,
             :reply_protocol
           ]),
         tool_calls when is_list(tool_calls) <- Keyword.get(options, :tool_calls, []),
         correlation when is_map(correlation) <- Keyword.get(options, :correlation, %{}),
         attempt when is_integer(attempt) and attempt > 0 <- Keyword.get(options, :attempt, 1),
         maximum_bytes when is_integer(maximum_bytes) and maximum_bytes > 0 <-
           Keyword.get(options, :maximum_bytes, 256 * 1_024),
         reply_protocol when reply_protocol in [:legacy, :mode_message_v1] <-
           Keyword.get(options, :reply_protocol, :legacy),
         true <- Enum.all?(tool_calls, &ToolCall.valid?/1) do
      speech? = speech_text?(text, reply_protocol, maximum_bytes)
      tool_only? = tool_calls != [] and not speech?

      %__MODULE__{
        text: text,
        tool_calls: tool_calls,
        speech?: speech?,
        tool_only?: tool_only?,
        correlation: correlation,
        attempt: attempt,
        maximum_bytes: maximum_bytes
      }
    else
      _invalid ->
        raise ArgumentError, "invalid round candidate"
    end
  end

  defp speech_text?(text, :legacy, _maximum) do
    String.trim(text) != ""
  end

  defp speech_text?(text, :mode_message_v1, maximum) do
    case Dialogue.decode(text, maximum) do
      {:ok, %{agent_mode: :speaker, message: message}} when is_binary(message) -> true
      _invalid -> false
    end
  end
end
