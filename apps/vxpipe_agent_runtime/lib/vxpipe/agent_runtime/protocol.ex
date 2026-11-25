defmodule Vxpipe.AgentRuntime.Protocol do
  @moduledoc "Combines publication-specific protocol instructions with shared policy at activation."

  alias Vxpipe.AgentRuntime.Prompt

  @pinned_names [:llm_dialogue, :conversation_summary]

  @spec capture(Path.t(), :legacy | :mode_message_v1) :: {:ok, map()} | {:error, atom()}
  def capture(
        directory \\ Application.app_dir(:vxpipe_agent_runtime, "priv/prompts"),
        version \\ :mode_message_v1
      )

  def capture(directory, version) when version in [:legacy, :mode_message_v1] do
    Enum.reduce_while(@pinned_names, {:ok, %{}}, fn name, {:ok, prompts} ->
      case Prompt.load(name, directory) do
        {:ok, prompt} ->
          value = %{"text" => prompt.text, "revision" => prompt.revision}
          {:cont, {:ok, Map.put(prompts, Atom.to_string(name), value)}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, prompts} ->
        {:ok,
         %{
           "version" => Atom.to_string(version),
           "prompts" => prompts,
           "shared_source" => "runtime"
         }}

      error ->
        error
    end
  end

  def capture(_directory, _version), do: {:error, :invalid_protocol}

  @spec validate(term()) :: :ok | {:error, :invalid_protocol}
  def validate(nil), do: :ok

  def validate(
        %{"version" => version, "prompts" => prompts, "shared_source" => "runtime"} = snapshot
      )
      when version in ["legacy", "mode_message_v1"] and map_size(snapshot) == 3 and
             is_map(prompts),
      do: validate_prompts(snapshot, prompts, @pinned_names)

  def validate(%{"version" => version, "prompts" => prompts} = snapshot)
      when version in ["legacy", "mode_message_v1"] and map_size(snapshot) == 2 and
             is_map(prompts),
      do: validate_prompts(snapshot, prompts, [:shared | @pinned_names])

  def validate(_snapshot), do: {:error, :invalid_protocol}

  defp validate_prompts(snapshot, prompts, names) do
    if map_size(prompts) == length(names) and
         Enum.all?(names, &match?({:ok, _}, prompt(snapshot, &1))),
       do: :ok,
       else: {:error, :invalid_protocol}
  end

  @spec reply_protocol(map() | nil) ::
          {:ok, :legacy | :mode_message_v1} | {:error, :invalid_protocol}
  def reply_protocol(snapshot) do
    with :ok <- validate(snapshot) do
      case snapshot do
        nil -> {:ok, :legacy}
        %{"version" => "legacy"} -> {:ok, :legacy}
        %{"version" => "mode_message_v1"} -> {:ok, :mode_message_v1}
      end
    end
  end

  @spec instructions(map() | nil, String.t(), :llm | :speech_to_speech) ::
          {:ok, String.t()} | {:error, :invalid_protocol | :prompt_unavailable}
  def instructions(snapshot, authored, kind)
      when is_binary(authored) and kind in [:llm, :speech_to_speech] do
    with :ok <- validate(snapshot),
         {:ok, shared} <- Prompt.load(:shared),
         {:ok, overlay} <- overlay(snapshot, kind) do
      {:ok, Enum.join([shared.text] ++ overlay ++ [authored], "\n\n")}
    end
  end

  def instructions(_snapshot, _authored, _kind), do: {:error, :invalid_protocol}

  @spec summary_prompt(map()) :: {:ok, Prompt.t()} | {:error, :invalid_protocol}
  def summary_prompt(snapshot) do
    with :ok <- validate(snapshot), do: prompt(snapshot, :conversation_summary)
  end

  defp overlay(%{"version" => "mode_message_v1"} = snapshot, :llm) do
    with {:ok, prompt} <- prompt(snapshot, :llm_dialogue), do: {:ok, [prompt.text]}
  end

  defp overlay(_snapshot, _kind), do: {:ok, []}

  defp prompt(%{"prompts" => prompts}, name) when is_map(prompts) do
    case Map.get(prompts, Atom.to_string(name)) do
      %{"text" => text, "revision" => revision} = value
      when map_size(value) == 2 and is_binary(text) and byte_size(text) <= 65_536 and
             is_binary(revision) and byte_size(revision) == 64 ->
        if String.valid?(text) and String.trim(text) != "" and
             revision == :crypto.hash(:sha256, text) |> Base.encode16(case: :lower) do
          {:ok, %Prompt{name: name, text: text, revision: revision}}
        else
          {:error, :invalid_protocol}
        end

      _invalid ->
        {:error, :invalid_protocol}
    end
  end

  defp prompt(_snapshot, _name), do: {:error, :invalid_protocol}
end
