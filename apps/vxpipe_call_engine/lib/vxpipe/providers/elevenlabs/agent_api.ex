defmodule Vxpipe.Providers.ElevenLabs.AgentAPI do
  @moduledoc "Bounded agent provisioning probe with explicit deletion and private signed connections."
  alias Vxpipe.Providers.{APIKeyCredential, ElevenLabs.AgentConnection}

  @enforce_keys [:api_key, :request]
  @derive {Inspect, only: []}
  defstruct @enforce_keys

  def new(api_key) do
    with :ok <- APIKeyCredential.validate("api_key", %{"api_key" => api_key}) do
      {:ok,
       %__MODULE__{
         api_key: api_key,
         request:
           Req.new(
             base_url: "https://api.elevenlabs.io",
             headers: [{"xi-api-key", api_key}],
             retry: false,
             redirect: false,
             receive_timeout: 10_000,
             connect_options: [timeout: 10_000]
           )
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def available_models(%__MODULE__{} = client) do
    with {:ok, %Req.Response{status: 200, body: %{"llms" => models}}} <-
           request(client, method: :get, url: "/v1/convai/llm/list"),
         true <- is_list(models) and length(models) <= 512,
         identifiers <- Enum.map(models, &Map.get(&1, "llm")),
         true <- Enum.all?(identifiers, &valid_model_id?(&1, client.api_key)) do
      {:ok, identifiers}
    else
      _failure -> {:error, :provider_unavailable}
    end
  rescue
    _exception -> {:error, :provider_unavailable}
  end

  # This bounded operation is for explicit provisioning/verification. Runtime
  # allocation needs a resource owner; this cannot clean up after VM termination
  # or an ambiguous create response which never supplied an agent ID.
  def with_agent(%__MODULE__{} = client, definition, consume)
      when is_map(definition) and is_function(consume, 1) do
    with {:ok, id} <- create(client, definition) do
      result = consume_connection(client, id, consume)

      case delete(client, id) do
        :ok -> result
        {:error, _reason} -> {:error, :cleanup_failed}
      end
    end
  end

  defp create(client, definition) do
    with {:ok, %Req.Response{status: 200, body: %{"agent_id" => id}}} <-
           request(client, method: :post, url: "/v1/convai/agents/create", json: definition),
         true <- valid_agent_id?(id) and id != client.api_key do
      {:ok, id}
    else
      {:ok, %Req.Response{status: 422, body: body}} ->
        {:error, {:provider_rejected, :create, 422, validation_fields(body)}}

      {:ok, %Req.Response{status: status, body: body}} when status != 200 ->
        case validation_fields(body) do
          [] -> {:error, {:provider_rejected, :create, status}}
          fields -> {:error, {:provider_rejected, :create, status, fields}}
        end

      _failure ->
        {:error, :provider_unavailable}
    end
  end

  defp consume_connection(client, id, consume) do
    with {:ok, %Req.Response{status: 200, body: %{"signed_url" => url}}} <-
           request(client,
             method: :get,
             url: "/v1/convai/conversation/get-signed-url",
             params: [agent_id: id]
           ),
         true <- is_binary(url) and not String.contains?(url, client.api_key),
         {:ok, connection} <- AgentConnection.new(url) do
      {:ok, consume.(connection)}
    else
      {:ok, %Req.Response{status: status}} when status != 200 ->
        {:error, {:provider_rejected, :sign, status}}

      _failure ->
        {:error, :provider_unavailable}
    end
  rescue
    _exception -> {:error, :consumer_failed}
  catch
    _, _reason -> {:error, :consumer_failed}
  end

  defp delete(client, id) do
    case request(client, method: :delete, url: "/v1/convai/agents/" <> id) do
      {:ok, %Req.Response{status: 204}} -> :ok
      _failure -> {:error, :provider_unavailable}
    end
  end

  defp request(client, options) do
    Req.request(client.request, options)
  rescue
    _exception -> {:error, :provider_unavailable}
  catch
    _, _reason -> {:error, :provider_unavailable}
  end

  defp valid_agent_id?(id) when is_binary(id),
    do: byte_size(id) in 1..256 and Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, id)

  defp valid_agent_id?(_invalid), do: false

  defp valid_model_id?(id, key) when is_binary(id),
    do: byte_size(id) in 1..128 and id != key and Regex.match?(~r/\A[A-Za-z0-9._@-]+\z/, id)

  defp valid_model_id?(_invalid, _key), do: false

  # Report only fixed field names or diagnostic words mentioned by validation;
  # these are hints, not an interpretation of the provider's rejection. Never return
  # provider messages, values, request content or externally supplied locations.
  defp validation_fields(body) do
    fields = ~w(retention_days max_duration_seconds thinking_budget llm voice_id
      model_id client_events initial_wait_time turn_timeout daily_limit
      reasoning_effort agent_concurrency_limit backup_llm_config
      subscription permission quota model)

    case JSON.encode!(body) do
      encoded when byte_size(encoded) <= 65_536 ->
        case Enum.filter(fields, &String.contains?(encoded, &1)) do
          [] -> diagnostic_words(String.downcase(encoded))
          matched -> matched
        end

      _invalid ->
        []
    end
  rescue
    _exception -> []
  end

  defp diagnostic_words(encoded) do
    ~w(limit duration voice language event turn budget agent auth invalid tool
      transcript retention privacy empty required deprecated format audio name
      create state daily concurrency usage temperature prompt thinking asr feature
      plan free enterprise unsupported disabled reasoning token minute)
    |> Enum.filter(&String.contains?(encoded, &1))
  end
end
