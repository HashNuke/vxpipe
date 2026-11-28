defmodule Vxpipe.Providers.Google.Decisions do
  @moduledoc false

  alias Vxpipe.Providers.{DecisionsRequest, DecisionsResponse, DecisionsTransport}

  @models ["gemini-decision-1"]
  @endpoint "https://generativelanguage.googleapis.com/v1beta/decisions"

  @enforce_keys [:api_key, :model]
  @derive {Inspect, only: [:model]}
  defstruct @enforce_keys

  @type t :: %__MODULE__{api_key: binary(), model: binary()}

  @spec models() :: [String.t()]
  def models, do: @models

  @spec endpoint() :: String.t()
  def endpoint, do: @endpoint

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_configuration}
  def new(options) when is_list(options) do
    with {:ok, validated} <- Keyword.validate(options, [:api_key, :model]),
         api_key when is_binary(api_key) <- Keyword.get(validated, :api_key),
         true <- byte_size(api_key) in 1..8_192,
         true <- Regex.match?(~r/\A[\x21-\x7E]+\z/, api_key),
         model when is_binary(model) <- Keyword.get(validated, :model),
         true <- model in @models do
      {:ok, %__MODULE__{api_key: api_key, model: model}}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  @spec resource_model(t()) :: String.t()
  def resource_model(%__MODULE__{model: model}), do: "models/" <> model

  @spec request_body(t(), binary() | map(), [map()]) ::
          {:ok, map()} | {:error, :invalid_request | :oversized}
  def request_body(%__MODULE__{} = config, evidence, questions) do
    DecisionsRequest.build(evidence, questions, :text, fn input, pairs ->
      questions =
        Map.new(pairs, fn {id, text} -> {id, %{"type" => "noul", "instructions" => text}} end)

      %{"model" => resource_model(config), "input" => input, "questions" => questions}
    end)
  end

  def request_body(_config, _evidence, _questions), do: {:error, :invalid_request}

  @spec evaluate(t(), binary() | map(), [map()], keyword()) ::
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
    with {:ok, body} <- request_body(config, evidence, questions) do
      ids = Map.keys(body["questions"])

      headers = [
        {"x-goog-api-key", config.api_key},
        {"content-type", "application/json"},
        {"accept", "application/json"}
      ]

      DecisionsTransport.post(@endpoint, headers, body, opts, %{
        retryable_statuses: [429, 503],
        parse: &parse_transport(&1, ids)
      })
    else
      {:error, _reason} = error -> error
    end
  end

  defp parse_transport(body, ids) when is_map(body) do
    refusal =
      case body["prompt_feedback"] do
        %{"block_reason" => reason} when is_binary(reason) ->
          String.trim(reason) not in ["", "BLOCK_REASON_UNSPECIFIED", "UNSPECIFIED", "UNKNOWN"]

        _ ->
          false
      end

    DecisionsResponse.nouls(body, ids, parse_usage(body), refusal)
  end

  defp parse_transport(_body, _ids), do: {:error, :invalid_result}

  defp parse_usage(body) do
    DecisionsTransport.reported_usage(body["usage"],
      input_tokens: "total_input_tokens",
      output_tokens: "total_output_tokens",
      total_tokens: "total_tokens"
    )
  end
end
