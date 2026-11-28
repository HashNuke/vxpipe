defmodule Vxpipe.Providers.Jev.Decisions do
  @moduledoc false

  alias Vxpipe.Providers.DecisionsTransport

  @endpoint "https://api.typesafe.ai/v1/systemone"
  @models ["jev-1.14.0", "jev-latest"]
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
         {:ok, encoded} <- encode_questions(questions) do
      body = %{model: config.model, state: evidence, questions: encoded}

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
        retryable_statuses: [429, 503, 529],
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
        case parse_nouls_with_partial(answers, ids) do
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

          {:partial, probabilities} ->
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

  defp fetch_answers(%{"answers" => answers}) when is_map(answers), do: {:ok, answers}
  defp fetch_answers(_body), do: :error

  defp fetch_model(%{"model" => model}) when is_binary(model) and byte_size(model) in 1..256,
    do: {:ok, model}

  defp fetch_model(_body), do: :error

  defp parse_nouls_with_partial(answers, ids) when is_map(answers) and is_list(ids) do
    keys = Map.keys(answers)
    trustworthy = trustworthy_nouls(answers, ids)

    if Enum.sort(keys) != Enum.sort(ids) do
      if trustworthy == %{}, do: :error, else: {:partial, trustworthy}
    else
      case parse_nouls(answers, ids) do
        {:ok, probabilities} -> {:ok, probabilities}
        :error when trustworthy != %{} -> {:partial, trustworthy}
        :error -> :error
      end
    end
  end

  defp parse_nouls(answers, ids) do
    keys = Map.keys(answers)

    if Enum.sort(keys) != Enum.sort(ids) do
      :error
    else
      Enum.reduce_while(ids, {:ok, %{}}, fn id, {:ok, acc} ->
        case Map.fetch(answers, id) do
          {:ok, %{"type" => "noul", "noul" => value}} ->
            case usable_probability(value) do
              {:ok, probability} -> {:cont, {:ok, Map.put(acc, id, probability)}}
              :error -> {:halt, :error}
            end

          _other ->
            {:halt, :error}
        end
      end)
    end
  end

  defp trustworthy_nouls(answers, ids) when is_map(answers) and is_list(ids) do
    Enum.reduce(ids, %{}, fn id, acc ->
      case Map.fetch(answers, id) do
        {:ok, %{"type" => "noul", "noul" => value}} ->
          case usable_probability(value) do
            {:ok, probability} -> Map.put(acc, id, probability)
            :error -> acc
          end

        _other ->
          acc
      end
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
      output_tokens: "output_tokens"
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
    Enum.reduce_while(questions, {:ok, %{}}, fn
      %{id: id, question: text}, {:ok, acc} when is_binary(id) and is_binary(text) ->
        with true <- Regex.match?(@id_pattern, id),
             true <- String.valid?(text),
             size <- byte_size(text),
             true <- size >= 1 and size <= @max_question_bytes,
             false <- Map.has_key?(acc, id) do
          {:cont, {:ok, Map.put(acc, id, %{type: "noul", instructions: text})}}
        else
          _invalid -> {:halt, {:error, :invalid_request}}
        end

      %{"id" => id, "question" => text}, {:ok, acc} ->
        if is_binary(id) and is_binary(text) and Regex.match?(@id_pattern, id) and
             String.valid?(text) and byte_size(text) in 1..@max_question_bytes and
             not Map.has_key?(acc, id) do
          {:cont, {:ok, Map.put(acc, id, %{type: "noul", instructions: text})}}
        else
          {:halt, {:error, :invalid_request}}
        end

      _other, _acc ->
        {:halt, {:error, :invalid_request}}
    end)
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
