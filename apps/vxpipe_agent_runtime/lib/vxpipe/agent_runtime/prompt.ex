defmodule Vxpipe.AgentRuntime.Prompt do
  @moduledoc "A bounded, packaged instruction source pinned by an activation."

  @derive {Inspect, only: [:name, :revision]}
  @enforce_keys [:name, :text, :revision]
  defstruct @enforce_keys

  @type t :: %__MODULE__{name: atom(), text: String.t(), revision: String.t()}
  @files %{
    shared: "agent-system.md",
    llm_dialogue: "llm-dialogue-system.md",
    conversation_summary: "conversation-summary-system.md"
  }

  @spec load(atom(), Path.t()) :: {:ok, t()} | {:error, :prompt_unavailable}
  def load(name, directory \\ Application.app_dir(:vxpipe_agent_runtime, "priv/prompts")) do
    with {:ok, filename} <- Map.fetch(@files, name),
         {:ok, text} <- File.read(Path.join(directory, filename)),
         true <- byte_size(text) <= 64 * 1_024 and String.valid?(text) and String.trim(text) != "" do
      text = String.trim(text)

      {:ok,
       %__MODULE__{
         name: name,
         text: text,
         revision: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
       }}
    else
      _invalid -> {:error, :prompt_unavailable}
    end
  end
end
