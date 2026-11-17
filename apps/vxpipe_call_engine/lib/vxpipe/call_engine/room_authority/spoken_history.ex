defmodule Vxpipe.CallEngine.RoomAuthority.SpokenHistory do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{Input, Message}
  alias Vxpipe.CallEngine.CallSpec.TransferHistory
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.TextToSpeechRequest

  @derive {Inspect, only: [:size]}
  @enforce_keys [:entries, :size]
  defstruct @enforce_keys

  @type entry ::
          Message.t() | %{required(:role) => :user | :assistant, required(:content) => String.t()}
  @type t :: %__MODULE__{entries: :queue.queue(entry()), size: non_neg_integer()}

  @spec new() :: t()
  def new, do: %__MODULE__{entries: :queue.new(), size: 0}

  @spec confirm_user(t(), String.t() | SendText.t()) :: t()
  def confirm_user(%__MODULE__{} = history, %SendText{model_input: %Input{} = input}) do
    append_message(history, Message.user(Input.encode(input)))
  end

  def confirm_user(%__MODULE__{} = history, %SendText{content: content}),
    do: confirm_user(history, content)

  def confirm_user(%__MODULE__{} = history, content) when is_binary(content) and content != "" do
    append(history, :user, content)
  end

  @spec played_assistant(t(), String.t() | TextToSpeechRequest.t()) :: t()
  def played_assistant(%__MODULE__{} = history, %TextToSpeechRequest{} = request) do
    {:ok, message} =
      Message.spoken_assistant(
        request.participant_id,
        request.text,
        :speaker,
        byte_size(request.text)
      )

    append_message(history, message)
  end

  def played_assistant(%__MODULE__{} = history, content)
      when is_binary(content) and content != "" do
    append(history, :assistant, content)
  end

  @spec project(t(), TransferHistory.t()) :: [Message.t()]
  def project(%__MODULE__{}, %TransferHistory{mode: mode}) when mode in [:fresh, :selected],
    do: []

  def project(%__MODULE__{} = history, %TransferHistory{mode: :all_spoken}) do
    history.entries
    |> :queue.to_list()
    |> messages()
  end

  def project(
        %__MODULE__{} = history,
        %TransferHistory{mode: :last_n_spoken, turns: turns}
      )
      when is_integer(turns) and turns > 0 do
    entries = :queue.to_list(history.entries)

    entries
    |> Enum.drop(max(length(entries) - turns, 0))
    |> messages()
  end

  defp append(history, role, content) do
    entry = %{role: role, content: content}
    %{history | entries: :queue.in(entry, history.entries), size: history.size + 1}
  end

  defp append_message(history, message),
    do: %{history | entries: :queue.in(message, history.entries), size: history.size + 1}

  defp messages(entries) do
    Enum.map(entries, fn
      %Message{} = message -> message
      %{role: :user, content: content} -> Message.user(content)
      %{role: :assistant, content: content} -> Message.assistant(content, [])
    end)
  end
end
