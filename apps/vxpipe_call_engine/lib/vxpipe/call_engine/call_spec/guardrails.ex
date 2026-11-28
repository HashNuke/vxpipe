defmodule Vxpipe.CallEngine.CallSpec.Guardrails do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.GuardrailQuestion
  alias Vxpipe.CallEngine.CallSpecValidation

  @events [:before_turn, :after_turn, :before_outgoing_transfer]
  @max_questions 32
  @max_text_bytes 16_384
  @max_question_bytes 1_024
  @max_response_bytes 1_024
  @default_threshold_hundredths 70
  @id_pattern ~r/\A[a-z][a-z0-9_]{0,63}\z/
  @threshold_pattern ~r/\A(0(\.\d{1,2})?|1(\.0{1,2})?)\z/

  defstruct before_turn: [], after_turn: [], before_outgoing_transfer: []

  @type t :: %__MODULE__{
          before_turn: [GuardrailQuestion.t()],
          after_turn: [GuardrailQuestion.t()],
          before_outgoing_transfer: [GuardrailQuestion.t()]
        }

  @type outcome :: %{
          question: GuardrailQuestion.t(),
          probability_yes: nil | number(),
          inferred_answer: nil | :yes | :no,
          outcome: :passed | :failed | :unavailable
        }

  @type evaluation :: %{status: :passed | :blocked | :error, outcomes: [outcome()]}

  @spec events() :: [:before_turn | :after_turn | :before_outgoing_transfer]
  def events, do: @events

  def empty?(%__MODULE__{} = policy), do: policy == %__MODULE__{}

  def required?(participants) do
    Enum.any?(participants, fn {_key, participant} -> not empty?(participant.guardrails) end)
  end

  def digest(%__MODULE__{} = policy) do
    canonical =
      for event <- @events do
        entries =
          for question <- Map.fetch!(policy, event) do
            {question.id, question.question, question.required_answer,
             question.threshold_hundredths, question.response}
          end

        {event, entries}
      end

    "sha256:" <>
      Base.encode16(
        :crypto.hash(:sha256, :erlang.term_to_binary({:guardrails_v1, canonical})),
        case: :lower
      )
  end

  @spec new(nil | map(), [String.t()]) :: {:ok, t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def new(nil, _path), do: {:ok, %__MODULE__{}}

  def new(value, path) when is_map(value) do
    code = :invalid_call_spec
    message = "The call spec is invalid."

    with {:ok, input} <-
           CallSpecValidation.normalize_map(value, @events, code, message, path),
         {:ok, before_turn} <-
           questions(Map.get(input, :before_turn, []), path ++ ["before_turn"]),
         {:ok, after_turn} <- questions(Map.get(input, :after_turn, []), path ++ ["after_turn"]),
         {:ok, transfer} <-
           questions(
             Map.get(input, :before_outgoing_transfer, []),
             path ++ ["before_outgoing_transfer"]
           ),
         :ok <- unique_ids([before_turn, after_turn, transfer], path) do
      {:ok,
       %__MODULE__{
         before_turn: before_turn,
         after_turn: after_turn,
         before_outgoing_transfer: transfer
       }}
    end
  end

  def new(_value, path) do
    CallSpecValidation.invalid(
      :invalid_call_spec,
      "The call spec is invalid.",
      path,
      "must be an object"
    )
  end

  @spec evaluate([GuardrailQuestion.t()], map()) :: {:ok, evaluation()} | {:error, evaluation()}
  def evaluate(questions, scores) when is_list(questions) and is_map(scores) do
    outcomes = Enum.map(questions, &score_question(&1, scores))

    unknown? = Enum.any?(scores, fn {id, _score} -> not Enum.any?(questions, &(&1.id == id)) end)
    unavailable? = Enum.any?(outcomes, &(&1.outcome == :unavailable))

    cond do
      unknown? or unavailable? ->
        {:error, %{status: :error, outcomes: outcomes}}

      Enum.any?(outcomes, &(&1.outcome == :failed)) ->
        {:ok, %{status: :blocked, outcomes: outcomes}}

      true ->
        {:ok, %{status: :passed, outcomes: outcomes}}
    end
  end

  @spec feedback(evaluation()) :: [String.t()]
  def feedback(%{status: :blocked, outcomes: outcomes}) do
    outcomes
    |> Enum.filter(&(&1.outcome == :failed))
    |> Enum.map(&feedback_line(&1.question))
  end

  def feedback(_evaluation), do: []

  @spec check_feedback_budget(t(), pos_integer()) :: :ok | {:error, :oversized}
  def check_feedback_budget(%__MODULE__{} = policy, max_bytes) do
    # Before-turn feedback is sent on its own. A spoken transfer can fail both
    # output checks and needs one repair request containing both ordered groups.
    candidates = [[:before_turn], [:after_turn, :before_outgoing_transfer]]

    oversized? =
      Enum.any?(candidates, fn events ->
        failures =
          for event <- events, questions = Map.fetch!(policy, event), questions != [] do
            %{event: event, messages: Enum.map(questions, &feedback_line/1)}
          end

        failures != [] and
          byte_size(Vxpipe.AgentRuntime.GuardrailFeedback.encode(failures)) > max_bytes
      end)

    if oversized?, do: {:error, :oversized}, else: :ok
  end

  defp questions(value, path) when is_list(value) do
    code = :invalid_call_spec
    message = "The call spec is invalid."

    with :ok <- check_count(value, path),
         {:ok, parsed} <- parse_questions(value, path),
         :ok <- check_text_bytes(parsed, path) do
      {:ok, parsed}
    else
      {:error, _error} = error -> error
      :error -> CallSpecValidation.invalid(code, message, path, "must be a list of questions")
    end
  end

  defp questions(_value, path) do
    CallSpecValidation.invalid(
      :invalid_call_spec,
      "The call spec is invalid.",
      path,
      "must be a list of questions"
    )
  end

  defp check_count(value, _path) when length(value) <= @max_questions, do: :ok

  defp check_count(_value, path) do
    CallSpecValidation.invalid(
      :invalid_call_spec,
      "The call spec is invalid.",
      path,
      "must contain at most #{@max_questions} questions"
    )
  end

  defp parse_questions(value, path) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, parsed} ->
      case question(item, path ++ [Integer.to_string(index)]) do
        {:ok, parsed_question} -> {:cont, {:ok, [parsed_question | parsed]}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      {:error, _error} = error -> error
    end
  end

  defp check_text_bytes(parsed, path) do
    total = Enum.reduce(parsed, 0, fn question, acc -> acc + byte_size(question.question) end)

    if total <= @max_text_bytes do
      :ok
    else
      CallSpecValidation.invalid(
        :invalid_call_spec,
        "The call spec is invalid.",
        path,
        "must contain at most #{@max_text_bytes} bytes of question text"
      )
    end
  end

  defp unique_ids(lists, path) do
    @events
    |> Enum.zip(lists)
    |> Enum.reduce_while({:ok, MapSet.new()}, fn {event, questions}, {:ok, seen} ->
      Enum.reduce_while(
        Enum.with_index(questions),
        {:ok, seen},
        fn {question, index}, {:ok, seen} ->
          if MapSet.member?(seen, question.id) do
            {:halt,
             CallSpecValidation.invalid(
               :invalid_call_spec,
               "The call spec is invalid.",
               path ++ [Atom.to_string(event), Integer.to_string(index), "id"],
               "must be unique within the participant"
             )}
          else
            {:cont, {:ok, MapSet.put(seen, question.id)}}
          end
        end
      )
      |> case do
        {:ok, seen} -> {:cont, {:ok, seen}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, _seen} -> :ok
      {:error, _error} = error -> error
    end
  end

  defp question(value, path) when not is_map(value) do
    CallSpecValidation.invalid(
      :invalid_call_spec,
      "The call spec is invalid.",
      path,
      "must be an object"
    )
  end

  defp question(value, path) do
    code = :invalid_call_spec
    message = "The call spec is invalid."

    with {:ok, input} <-
           CallSpecValidation.normalize_map(
             value,
             [:id, :question, :required_answer, :probability_threshold, :response],
             code,
             message,
             path
           ),
         {:ok, id} <- question_id(Map.get(input, :id), code, message, path),
         {:ok, text} <-
           CallSpecValidation.string(
             Map.get(input, :question),
             code,
             message,
             path ++ ["question"],
             maximum: @max_question_bytes
           ),
         {:ok, required} <- required_answer(input, code, message, path),
         {:ok, threshold} <-
           threshold(Map.get(input, :probability_threshold), code, message, path),
         {:ok, response} <- question_response(Map.get(input, :response), code, message, path) do
      {:ok,
       %GuardrailQuestion{
         id: id,
         question: text,
         required_answer: required,
         threshold_hundredths: threshold,
         response: response
       }}
    end
  end

  defp question_id(value, code, message, path) when is_binary(value) do
    if Regex.match?(@id_pattern, value) do
      {:ok, value}
    else
      CallSpecValidation.invalid(
        code,
        message,
        path ++ ["id"],
        "must match [a-z][a-z0-9_]{0,63}"
      )
    end
  end

  defp question_id(_value, code, message, path) do
    CallSpecValidation.invalid(code, message, path ++ ["id"], "is required")
  end

  defp required_answer(input, code, message, path) do
    with {:ok, value} <- CallSpecValidation.fetch(input, :required_answer, code, message, path) do
      CallSpecValidation.enum(
        value,
        [yes: "yes", no: "no"],
        code,
        message,
        path ++ ["required_answer"]
      )
    end
  end

  defp threshold(nil, _code, _message, _path), do: {:ok, @default_threshold_hundredths}
  defp threshold(0, _code, _message, _path), do: {:ok, 0}
  defp threshold(1, _code, _message, _path), do: {:ok, 100}
  defp threshold(1.0, _code, _message, _path), do: {:ok, 100}

  defp threshold(value, code, message, path) when is_float(value) do
    if value >= 0.0 and value <= 1.0 and value == value and
         Regex.match?(@threshold_pattern, Float.to_string(value)) do
      {:ok, decimal_to_hundredths(Float.to_string(value))}
    else
      CallSpecValidation.invalid(
        code,
        message,
        path ++ ["probability_threshold"],
        "must be between 0.00 and 1.00 in hundredth increments"
      )
    end
  end

  defp threshold(_value, code, message, path) do
    CallSpecValidation.invalid(
      code,
      message,
      path ++ ["probability_threshold"],
      "must be between 0.00 and 1.00 in hundredth increments"
    )
  end

  defp decimal_to_hundredths(decimal) do
    {whole, fraction} =
      case String.split(decimal, ".") do
        [whole] -> {whole, ""}
        [whole, fraction] -> {whole, fraction}
      end

    String.to_integer(whole) * 100 +
      (fraction |> String.pad_trailing(2, "0") |> String.to_integer())
  end

  defp question_response(nil, _code, _message, _path), do: {:ok, nil}

  defp question_response(value, code, message, path)
       when is_binary(value) and byte_size(value) <= @max_response_bytes do
    if String.valid?(value) do
      {:ok, value}
    else
      CallSpecValidation.invalid(code, message, path ++ ["response"], "must be valid UTF-8 text")
    end
  end

  defp question_response(_value, code, message, path) do
    CallSpecValidation.invalid(
      code,
      message,
      path ++ ["response"],
      "must be a string of at most #{@max_response_bytes} bytes"
    )
  end

  defp score_question(%GuardrailQuestion{id: id} = question, scores) do
    case Map.fetch(scores, id) do
      {:ok, score} ->
        case usable_score(score) do
          {:ok, probability} ->
            inferred = if probability >= question.threshold_hundredths / 100, do: :yes, else: :no

            %{
              question: question,
              probability_yes: probability,
              inferred_answer: inferred,
              outcome: if(inferred == question.required_answer, do: :passed, else: :failed)
            }

          :error ->
            %{
              question: question,
              probability_yes: nil,
              inferred_answer: nil,
              outcome: :unavailable
            }
        end

      :error ->
        %{question: question, probability_yes: nil, inferred_answer: nil, outcome: :unavailable}
    end
  end

  defp usable_score(score) when is_integer(score) and score >= 0 and score <= 1, do: {:ok, score}

  defp usable_score(score) when is_float(score) and score >= 0.0 and score <= 1.0 do
    if score == score, do: {:ok, score}, else: :error
  end

  defp usable_score(_score), do: :error

  defp feedback_line(%GuardrailQuestion{} = question) do
    {line, _origin} =
      GuardrailQuestion.feedback(question.question, question.required_answer, question.response)

    line
  end
end
