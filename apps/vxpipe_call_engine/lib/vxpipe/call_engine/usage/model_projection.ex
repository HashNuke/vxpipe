defmodule Vxpipe.CallEngine.Usage.ModelProjection do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.Correlation

  alias Vxpipe.CallEngine.Usage.{
    Attribution,
    Measurement,
    Observation,
    ProviderContext
  }

  @token_components ["input_tokens", "output_tokens", "total_tokens"]

  @spec project(map(), Correlation.t(), ProviderContext.t(), keyword()) ::
          {:ok, [Observation.t()]} | {:error, :invalid_model_usage}
  def project(data, correlation, provider, options)
      when is_map(data) and is_struct(correlation, Correlation) and
             is_struct(provider, ProviderContext) and is_list(options) do
    options = Keyword.put_new(options, :observed_at, DateTime.utc_now(:millisecond))

    with {:ok, options} <- validate_options(options),
         {:ok, attribution} <- attribution(correlation, options),
         {:ok, provider} <- provider_context(provider, provider_metadata(data)),
         {:ok, observations} <-
           observations(data, correlation, provider, attribution, options) do
      {:ok, observations}
    else
      _invalid -> {:error, :invalid_model_usage}
    end
  end

  def project(_data, _correlation, _provider, _options),
    do: {:error, :invalid_model_usage}

  defp validate_options(options) do
    with {:ok, options} <-
           Keyword.validate(options, [
             :call_id,
             :activation_id,
             :attempt_id,
             :observed_at,
             tool_call_id: nil
           ]),
         {:ok, _call_id} <- Keyword.fetch(options, :call_id),
         {:ok, _activation_id} <- Keyword.fetch(options, :activation_id),
         {:ok, _attempt_id} <- Keyword.fetch(options, :attempt_id),
         {:ok, _observed_at} <- Keyword.fetch(options, :observed_at) do
      {:ok, options}
    end
  end

  defp attribution(correlation, options) do
    context = correlation.tool_context

    Attribution.new(
      room_id: context.room_id,
      incarnation_id: context.incarnation_id,
      participant_id: context.agent_participant_id,
      activation_id: Keyword.fetch!(options, :activation_id),
      turn_id: context.correlation_id,
      tool_call_id: Keyword.get(options, :tool_call_id)
    )
  end

  defp provider_context(configured, metadata) do
    model = external_identifier(fetch(metadata, :model)) || configured.model

    ProviderContext.new(
      name: provider_name(model, configured.name),
      integration_id: configured.integration_id,
      model: model,
      voice: configured.voice,
      request_id: external_identifier(fetch(metadata, :request_id)) || configured.request_id,
      operation_id:
        external_identifier(fetch(metadata, :operation_id)) ||
          external_identifier(fetch(metadata, :response_id)) || configured.operation_id,
      session_id: external_identifier(fetch(metadata, :session_id)) || configured.session_id
    )
  end

  defp observations(data, correlation, provider, attribution, options) do
    attempt_id = Keyword.fetch!(options, :attempt_id)
    usage = usage(data)

    measurements =
      @token_components
      |> Enum.flat_map(&measurement(usage, &1))
      |> add_inclusion_relations()

    measurements = if measurements == [], do: [nil], else: measurements

    measurements
    |> Enum.reduce_while({:ok, []}, fn measurement, {:ok, observations} ->
      component = if measurement, do: measurement.component, else: "operation"

      case Observation.new(
             id: observation_id(attempt_id, component),
             tenant_id: correlation.tool_context.tenant_id,
             call_id: Keyword.fetch!(options, :call_id),
             attempt_id: attempt_id,
             capability: :model_inference,
             provider: provider,
             attribution: attribution,
             measurement: measurement,
             outcome: :succeeded,
             observed_at: Keyword.fetch!(options, :observed_at)
           ) do
        {:ok, observation} -> {:cont, {:ok, [observation | observations]}}
        {:error, :invalid_observation} -> {:halt, {:error, :invalid_model_usage}}
      end
    end)
    |> case do
      {:ok, observations} -> {:ok, Enum.reverse(observations)}
      {:error, :invalid_model_usage} = error -> error
    end
  end

  defp measurement(usage, component) do
    case fetch(usage, component) do
      quantity when is_integer(quantity) and quantity >= 0 ->
        {:ok, measurement} =
          Measurement.new(
            component: component,
            unit: :tokens,
            quantity: quantity,
            mode: :cumulative,
            status: :final,
            provenance: :provider_reported
          )

        [measurement]

      _unavailable ->
        []
    end
  end

  defp add_inclusion_relations(measurements) do
    if Enum.any?(measurements, &(&1.component == "total_tokens")) do
      Enum.map(measurements, fn
        %Measurement{component: component} = measurement
        when component in ["input_tokens", "output_tokens"] ->
          %{measurement | included_in: "total_tokens"}

        measurement ->
          measurement
      end)
    else
      measurements
    end
  end

  defp usage(data) do
    case fetch(data, :usage) do
      usage when is_map(usage) -> usage
      _unavailable -> %{}
    end
  end

  defp provider_metadata(data) do
    case fetch(data, :provider_metadata) do
      metadata when is_map(metadata) -> metadata
      _unavailable -> %{}
    end
  end

  defp fetch(map, key) when is_atom(key),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp fetch(map, key) when is_binary(key),
    do: Map.get(map, key) || Map.get(map, String.to_existing_atom(key))

  defp external_identifier(value)
       when is_binary(value) and byte_size(value) <= 256 and value != "[REDACTED]" do
    if String.trim(value) == "", do: nil, else: value
  end

  defp external_identifier(_value), do: nil

  defp provider_name(model, fallback) when is_binary(model) do
    case String.split(model, ":", parts: 2) do
      [name, _model] when name != "" -> name
      _other -> fallback
    end
  end

  defp provider_name(_model, fallback), do: fallback

  defp observation_id(attempt_id, component) do
    digest = :crypto.hash(:sha256, attempt_id <> ":" <> component)
    "uobs_" <> Base.url_encode64(digest, padding: false)
  end
end
