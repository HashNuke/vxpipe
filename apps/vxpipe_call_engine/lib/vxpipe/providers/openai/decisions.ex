defmodule Vxpipe.Providers.OpenAI.Decisions do
  @moduledoc false

  alias Vxpipe.Providers.DecisionsTransport

  @endpoint "https://api.openai.com/v1/decisions"
  @models ["gpt-6-luna"]
  @max_evidence_bytes 49_152
  @max_questions 32
  @max_question_bytes 1_024
  @id_pattern ~r/\A[a-z][a-z0-9_]{0,63}\z/

  @enforce_keys [:api_key, :model]
  @derive {Inspect, only: [:model]}
  defstruct @enforce_keys ++ [endpoint: @endpoint]

  @type t :: %__MODULE__{api_key: binary(), model: binary(), endpoint: binary()}

  @spec models() :: [String.t()]
  def models, do: @models

  @spec endpoint() :: String.t()
  def endpoint, do: @endpoint

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_configuration}
  def new(options) when is_list(options) do
    with {:ok, validated} <- Keyword.validate(options, [:api_key, :model, :endpoint]),
         api_key when is_binary(api_key) <- Keyword.get(validated, :api_key),
         true <- byte_size(api_key) in 1..8_192,
         true <- Regex.match?(~r/\A[\x21-\x7E]+\z/, api_key),
         model when is_binary(model) <- Keyword.get(validated, :model),
         true <- model in @models,
         endpoint <- Keyword.get(validated, :endpoint, @endpoint),
         true <- is_binary(endpoint) and String.starts_with?(endpoint, "https://") do
      {:ok, %__MODULE__{api_key: api_key, model: model, endpoint: endpoint}}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  @spec request_body(t(), binary(), [map()]) ::
          {:ok, map()} | {:error, :invalid_request | :oversized}
  def request_body(%__MODULE__{} = config, evidence, questions)
      when is_binary(evidence) and is_list(questions) do
    with :ok <- validate_evidence(evidence),
         {:ok, encoded_questions} <- encode_questions(questions) do
      body = %{model: config.model, input: evidence, questions: encoded_questions}

      if byte_size(JSON.encode!(body)) <= @max_evidence_bytes do
        {:ok, body}
      else
        {:error, :oversized}
      end
    end
  end

  def request_body(_config, _evidence, _questions), do: {:error, :invalid_request}

  @spec evaluate(t(), binary(), [map()], keyword()) ::
          {:ok,
           %{
             model: binary() | nil,
             request_id: binary() | nil,
             probabilities: %{String.t() => float()},
             usage: map() | :unknown,
             attempts: 1 | 2,
             elapsed_ms: non_neg_integer()
           }}
          | {:error, atom()}
  def evaluate(%__MODULE__{} = config, evidence, questions, opts \\ []) when is_list(opts) do
    with {:ok, body} <- request_body(config, evidence, questions),
         {:ok, ids} <- question_ids(questions) do
      headers = [
        {"authorization", "Bearer " <> config.api_key},
        {"content-type", "application/json"},
        {"accept", "application/json"}
      ]

      DecisionsTransport.post(config.endpoint, headers, body, opts, %{
        retryable_statuses: [429, 503],
        parse: &parse_transport(&1, ids)
      })
    else
      {:error, _reason} = error -> error
    end
  end

  defp parse_transport(body, ids) when is_map(body) do
    request_id = DecisionsTransport.extract_request_id(body)
    usage = parse_usage(body)

    case fetch_answers(body) do
      {:ok, answers} ->
        case parse_predicates_with_partial(answers, ids) do
          {:ok, probabilities} ->
            case fetch_model(body) do
              {:ok, model} ->
                {:ok,
                 %{
                   model: model,
                   request_id: request_id,
                   usage: usage,
                   probabilities: probabilities
                 }}

              :error ->
                {:error, :invalid_result,
                 %{model: nil, request_id: request_id, usage: usage, probabilities: probabilities}}
            end

          {:partial, probabilities, :refused} ->
            model =
              case fetch_model(body) do
                {:ok, model} -> model
                :error -> nil
              end

            {:error, :refused,
             %{model: model, request_id: request_id, usage: usage, probabilities: probabilities}}

          {:partial, probabilities, _reason} ->
            model =
              case fetch_model(body) do
                {:ok, model} -> model
                :error -> nil
              end

            {:error, :invalid_result,
             %{model: model, request_id: request_id, usage: usage, probabilities: probabilities}}

          :error ->
            {:error, :invalid_result,
             %{model: nil, request_id: request_id, usage: usage, probabilities: nil}}
        end

      :error ->
        {:error, :invalid_result,
         %{model: nil, request_id: request_id, usage: usage, probabilities: nil}}
    end
  end

  defp parse_transport(_body, _ids), do: {:error, :invalid_result}

  defp fetch_answers(%{"answers" => answers}) when is_list(answers), do: {:ok, answers}
  defp fetch_answers(_body), do: :error

  defp fetch_model(%{"model" => model}) when is_binary(model) and byte_size(model) in 1..256,
    do: {:ok, model}

  defp fetch_model(_body), do: :error

  defp parse_predicates_with_partial(answers, ids) do
    names =
      Enum.map(answers, fn
        %{"name" => name} -> name
        _other -> :invalid
      end)

    refused? =
      Enum.any?(answers, &match?(%{"type" => "refusal", "name" => _}, &1)) or
        Enum.any?(answers, &match?(%{"type" => "refusal"}, &1))

    trustworthy = trustworthy_predicates(answers, ids)

    cond do
      length(answers) != length(ids) ->
        if trustworthy == %{}, do: :error, else: {:partial, trustworthy, :invalid_result}

      Enum.sort(names) != Enum.sort(ids) ->
        if trustworthy == %{}, do: :error, else: {:partial, trustworthy, :invalid_result}

      length(Enum.uniq(names)) != length(names) ->
        if trustworthy == %{}, do: :error, else: {:partial, trustworthy, :invalid_result}

      refused? ->
        {:partial, trustworthy, :refused}

      true ->
        case collect_probabilities(answers) do
          {:ok, probabilities} -> {:ok, probabilities}
          :error when trustworthy != %{} -> {:partial, trustworthy, :invalid_result}
          :error -> :error
        end
    end
  end

  defp trustworthy_predicates(answers, ids) when is_list(answers) and is_list(ids) do
    ids_set = MapSet.new(ids)
    ambiguous = ambiguous_names(answers)

    answers
    |> Enum.reduce(%{}, fn
      %{"type" => "predicate", "name" => name, "probability" => probability}, acc
      when is_binary(name) ->
        if MapSet.member?(ids_set, name) and not MapSet.member?(ambiguous, name) and
             not Map.has_key?(acc, name) do
          case usable_probability(probability) do
            {:ok, value} -> Map.put(acc, name, value)
            :error -> acc
          end
        else
          acc
        end

      _other, acc ->
        acc
    end)
  end

  # Any id occurring more than once across the raw answer list is ambiguous:
  # with conflicting duplicates we cannot tell which occurrence (if any) is
  # trustworthy, so every occurrence is excluded from partial scores.
  defp ambiguous_names(answers) do
    answers
    |> Enum.reduce(%{}, fn
      %{"name" => name}, acc when is_binary(name) -> Map.update(acc, name, 1, &(&1 + 1))
      _other, acc -> acc
    end)
    |> Enum.reduce(MapSet.new(), fn
      {name, count}, acc when count > 1 -> MapSet.put(acc, name)
      _entry, acc -> acc
    end)
  end

  defp collect_probabilities(answers) do
    Enum.reduce_while(answers, {:ok, %{}}, fn
      %{"type" => "predicate", "name" => name, "probability" => probability}, {:ok, acc}
      when is_binary(name) ->
        case usable_probability(probability) do
          {:ok, value} -> {:cont, {:ok, Map.put(acc, name, value)}}
          :error -> {:halt, :error}
        end

      _other, _acc ->
        {:halt, :error}
    end)
  end

  defp usable_probability(value) when is_integer(value) and value in [0, 1],
    do: {:ok, value * 1.0}

  defp usable_probability(value) when is_float(value) and value >= 0.0 and value <= 1.0 do
    if value == value, do: {:ok, value}, else: :error
  end

  defp usable_probability(_value), do: :error

  defp parse_usage(body) do
    DecisionsTransport.reported_usage(body["usage"],
      input_tokens: "input_tokens",
      output_tokens: "output_tokens",
      total_tokens: "total_tokens"
    )
  end

  defp validate_evidence(evidence) when is_binary(evidence) do
    cond do
      not String.valid?(evidence) -> {:error, :invalid_request}
      byte_size(evidence) < 1 -> {:error, :invalid_request}
      byte_size(evidence) > @max_evidence_bytes -> {:error, :oversized}
      true -> :ok
    end
  end

  defp validate_evidence(_evidence), do: {:error, :invalid_request}

  defp encode_questions(questions)
       when length(questions) < 1 or length(questions) > @max_questions do
    {:error, :oversized}
  end

  defp encode_questions(questions) do
    Enum.reduce_while(questions, {:ok, []}, fn
      %{id: id, question: text}, {:ok, acc} when is_binary(id) and is_binary(text) ->
        with true <- Regex.match?(@id_pattern, id),
             true <- String.valid?(text),
             size <- byte_size(text),
             true <- size >= 1 and size <= @max_question_bytes do
          {:cont, {:ok, [%{name: id, type: "predicate", instructions: text} | acc]}}
        else
          _invalid -> {:halt, {:error, :invalid_request}}
        end

      %{"id" => id, "question" => text}, {:ok, acc} ->
        if is_binary(id) and is_binary(text) and Regex.match?(@id_pattern, id) and
             String.valid?(text) and byte_size(text) in 1..@max_question_bytes do
          {:cont, {:ok, [%{name: id, type: "predicate", instructions: text} | acc]}}
        else
          {:halt, {:error, :invalid_request}}
        end

      _other, _acc ->
        {:halt, {:error, :invalid_request}}
    end)
    |> case do
      {:ok, reversed} ->
        names = Enum.map(reversed, & &1.name)

        if length(Enum.uniq(names)) == length(names) do
          {:ok, Enum.reverse(reversed)}
        else
          {:error, :invalid_request}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp question_ids(questions) do
    ids =
      Enum.map(questions, fn
        %{id: id} when is_binary(id) -> id
        %{"id" => id} when is_binary(id) -> id
        _other -> :invalid
      end)

    if Enum.any?(ids, &(&1 == :invalid)) or length(Enum.uniq(ids)) != length(ids) do
      {:error, :invalid_request}
    else
      {:ok, ids}
    end
  end
end
