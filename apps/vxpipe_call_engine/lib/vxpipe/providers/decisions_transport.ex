defmodule Vxpipe.Providers.DecisionsTransport do
  @moduledoc false

  @default_timeout_ms 2_000

  @type on_attempt :: (map() -> any())

  @spec post(String.t(), [{String.t(), String.t()}], map(), keyword(), map()) ::
          {:ok,
           %{
             model: binary() | nil,
             request_id: binary() | nil,
             probabilities: %{String.t() => float()},
             usage: map() | :unknown,
             attempts: pos_integer(),
             elapsed_ms: non_neg_integer()
           }}
          | {:error, atom()}
  def post(endpoint, headers, json_body, opts, callbacks)
      when is_binary(endpoint) and is_list(headers) and is_map(json_body) and is_list(opts) and
             is_map(callbacks) do
    started = now()

    transport = %{
      endpoint: endpoint,
      request_options:
        [headers: headers, json: json_body, retry: false, redirect: false, decode_body: false] ++
          Keyword.take(opts, [:plug]),
      parse: Map.fetch!(callbacks, :parse),
      retryable_statuses: Map.get(callbacks, :retryable_statuses, [429, 503]),
      on_attempt: normalize_observer(Keyword.get(opts, :on_attempt)),
      deadline: Keyword.get(opts, :deadline_ms) || started + @default_timeout_ms,
      started: started,
      cancelled?: Keyword.get(opts, :cancelled),
      http: Keyword.get(opts, :http_fun, &Req.post/2),
      sleep: Keyword.get(opts, :sleep, &Process.sleep/1)
    }

    attempt(transport, 1)
  end

  defp attempt(transport, ordinal) do
    started = now()

    with :ok <- admission(transport),
         :ok <-
           notify(transport.on_attempt, %{
             phase: :started,
             ordinal: ordinal,
             started_at_ms: started
           }) do
      timeout = max(1, transport.deadline - now())

      request_options =
        transport.request_options ++
          [receive_timeout: timeout, connect_options: [timeout: timeout]]

      response = post_request(transport, request_options)
      {outcome, metadata, retry} = result(response, transport, ordinal)
      ended = now()
      elapsed = ended - transport.started

      event = %{
        phase: :finished,
        ordinal: ordinal,
        started_at_ms: started,
        ended_at_ms: ended,
        duration_ms: ended - started,
        elapsed_ms: elapsed,
        outcome: if(outcome == :ok, do: :succeeded, else: :failed),
        error_code: if(outcome == :ok, do: nil, else: outcome),
        model: safe_model(metadata),
        usage: safe_usage(metadata),
        request_id: safe_request_id(metadata),
        probabilities: safe_partial_probabilities(metadata)
      }

      notify(transport.on_attempt, event)

      case {outcome, retry} do
        {:ok, _} ->
          with :ok <- admission(transport) do
            {:ok,
             %{
               model: event.model,
               usage: event.usage,
               request_id: event.request_id,
               probabilities: metadata.probabilities,
               attempts: ordinal,
               elapsed_ms: elapsed
             }}
          end

        {_reason, {:after, delay}} ->
          with :ok <- admission(transport) do
            if delay < transport.deadline - now() do
              transport.sleep.(delay)
              attempt(transport, 2)
            else
              {:error, :retry_exhausted}
            end
          end

        {reason, nil} ->
          {:error, reason}
      end
    end
  end

  defp post_request(transport, options) do
    transport.http.(transport.endpoint, options)
  rescue
    _error -> {:error, :transport_error}
  catch
    :exit, _reason -> {:error, :transport_error}
  end

  defp result({:ok, %Req.Response{status: 200} = response}, transport, _ordinal) do
    parsed =
      with {:ok, body} <- decode_body(response.body) do
        safe_parse(transport.parse, body)
      end

    {outcome, metadata} =
      case parsed do
        {:ok, %{probabilities: scores} = details} when is_map(scores) -> {:ok, details}
        {:error, reason, details} when is_atom(reason) and is_map(details) -> {reason, details}
        {:error, reason} when is_atom(reason) -> {reason, %{}}
        _invalid -> {:invalid_result, %{}}
      end

    request_id = request_id_header(response) || safe_request_id(metadata)
    {outcome, Map.put(metadata, :request_id, request_id), nil}
  end

  defp result({:ok, %Req.Response{status: status} = response}, transport, ordinal) do
    metadata = %{request_id: request_id_header(response)}

    cond do
      status in transport.retryable_statuses and ordinal == 1 ->
        {retry_error_code(status), metadata, {:after, retry_delay(response)}}

      status in transport.retryable_statuses ->
        {:retry_exhausted, metadata, nil}

      status in [401, 403] ->
        {:unauthorized, metadata, nil}

      status >= 500 ->
        {:unavailable, metadata, nil}

      true ->
        {:invalid_result, metadata, nil}
    end
  end

  defp result({:error, %Req.TransportError{reason: reason}}, _, _)
       when reason in [:timeout, :receive_timeout, :connect_timeout], do: {:timeout, %{}, nil}

  defp result(_response, _, _), do: {:transport_error, %{}, nil}

  # Named answers must survive decoding without choosing a winner for duplicate IDs.
  # The adapters treat a duplicate value as invalid and can still read unaffected answers.
  defp decode_body(raw) when is_binary(raw) do
    decoders = [
      object_start: fn _ -> %{} end,
      object_push: fn key, value, map ->
        Map.update(map, key, value, fn _ -> :duplicate_json_key end)
      end,
      object_finish: fn map, parent -> {map, parent} end
    ]

    case JSON.decode(raw, nil, decoders) do
      {body, nil, ""} when is_map(body) -> {:ok, body}
      _ -> {:error, :invalid_result}
    end
  end

  defp decode_body(body) when is_map(body), do: {:ok, body}
  defp decode_body(_), do: {:error, :invalid_result}

  defp request_id_header(response) do
    case Req.Response.get_header(response, "x-request-id") do
      [id] when is_binary(id) and byte_size(id) in 1..256 -> id
      _ -> nil
    end
  end

  defp safe_parse(parse, body) when is_function(parse, 1) do
    try do
      parse.(body)
    rescue
      _ -> {:error, :invalid_result}
    catch
      _, _ -> {:error, :invalid_result}
    end
  end

  defp safe_model(%{model: model}) when is_binary(model) and byte_size(model) in 1..256, do: model
  defp safe_model(_), do: nil

  defp safe_request_id(%{request_id: id}) when is_binary(id) and byte_size(id) in 1..256, do: id

  defp safe_request_id(%{"request_id" => id}) when is_binary(id) and byte_size(id) in 1..256,
    do: id

  defp safe_request_id(%{"id" => id}) when is_binary(id) and byte_size(id) in 1..256, do: id
  defp safe_request_id(_), do: nil

  @doc false
  def reported_usage(usage, fields) when is_map(usage) do
    counters =
      for {component, key} <- fields,
          value = Map.get(usage, key),
          is_integer(value) and value >= 0,
          into: %{},
          do: {component, value}

    if map_size(counters) > 0, do: counters, else: :unknown
  end

  def reported_usage(_absent, _fields), do: :unknown

  defp safe_usage(%{usage: usage}),
    do:
      reported_usage(usage,
        input_tokens: :input_tokens,
        output_tokens: :output_tokens,
        total_tokens: :total_tokens
      )

  defp safe_usage(_), do: :unknown

  defp safe_partial_probabilities(%{probabilities: probs}) when is_map(probs) do
    filtered =
      Enum.filter(probs, fn
        {k, v} when is_binary(k) and is_float(v) -> v >= 0.0 and v <= 1.0 and v == v
        {k, v} when is_binary(k) and is_integer(v) -> v in [0, 1]
        _ -> false
      end)
      |> Map.new(fn
        {k, v} when is_integer(v) -> {k, v * 1.0}
        {k, v} -> {k, v}
      end)

    if map_size(filtered) == 0, do: nil, else: filtered
  end

  defp safe_partial_probabilities(_), do: nil

  def extract_request_id(%{"id" => id}) when is_binary(id) and byte_size(id) in 1..256, do: id

  def extract_request_id(%{"request_id" => id}) when is_binary(id) and byte_size(id) in 1..256,
    do: id

  def extract_request_id(%{"requestId" => id}) when is_binary(id) and byte_size(id) in 1..256,
    do: id

  def extract_request_id(_), do: nil

  defp retry_error_code(429), do: :rate_limited
  defp retry_error_code(_), do: :unavailable

  defp normalize_observer(fun) when is_function(fun, 1), do: fun
  defp normalize_observer(_), do: nil

  defp notify(nil, _event), do: :ok

  defp notify(fun, event) when is_function(fun, 1) do
    try do
      case fun.(event) do
        {:error, :cancelled} -> {:error, :cancelled}
        _ -> :ok
      end
    rescue
      _ -> :ok
    catch
      :exit, _ -> {:error, :cancelled}
      _, _ -> :ok
    end
  end

  defp admission(transport) do
    cond do
      is_function(transport.cancelled?, 0) and transport.cancelled?.() -> {:error, :cancelled}
      transport.deadline <= now() -> {:error, :timeout}
      true -> :ok
    end
  end

  defp retry_delay(response) do
    Req.Response.get_retry_after(response) || 50
  rescue
    _invalid_header in [ArgumentError, CaseClauseError] -> 50
  end

  defp now, do: System.monotonic_time(:millisecond)
end
