defmodule Vxpipe.AgentRuntime.Provider.ReqLLM do
  @moduledoc "The production ReqLLM provider boundary."

  @behaviour Vxpipe.AgentRuntime.ModelProvider

  alias Elixir.ReqLLM.{Response, StreamResponse}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM.{Config, RequestProjection, ResponseNormalizer}

  @spec new(keyword()) :: {:ok, Config.t()} | {:error, :invalid_configuration}
  defdelegate new(options), to: Config

  @spec streaming?(Config.t()) :: boolean()
  @impl true
  def streaming?(%Config{} = config), do: config.streaming

  @doc false
  @spec prepare_request(Config.t(), Vxpipe.AgentRuntime.ModelRequest.t()) ::
          {term(), Elixir.ReqLLM.Context.t(), keyword()}
  defdelegate prepare_request(config, request), to: RequestProjection, as: :prepare

  @impl true
  def generate(%Config{} = config, request) do
    {model, context, options} = prepare_request(config, request)

    case Elixir.ReqLLM.generate_text(model, context, options) do
      {:ok, %Response{} = response} -> ResponseNormalizer.normalize(response)
      {:error, _reason} -> {:error, :provider_unavailable}
    end
  rescue
    _error -> {:error, :provider_unavailable}
  catch
    _kind, _reason -> {:error, :provider_unavailable}
  end

  @impl true
  def stream(%Config{} = config, request, emit) when is_function(emit, 1) do
    {model, context, options} = prepare_request(config, request)

    case Elixir.ReqLLM.stream_text(model, context, options) do
      {:ok, %StreamResponse{} = response} -> consume_stream(response, emit)
      {:error, _reason} -> {:error, :provider_unavailable}
    end
  rescue
    _error -> {:error, :provider_unavailable}
  catch
    _kind, _reason -> {:error, :provider_unavailable}
  end

  @doc false
  @spec consume_stream(StreamResponse.t(), (String.t() -> :ok | {:error, atom()})) ::
          {:ok, Vxpipe.AgentRuntime.ModelResponse.t()} | {:error, atom()}
  def consume_stream(%StreamResponse{} = stream_response, emit) when is_function(emit, 1) do
    case StreamResponse.process_stream(stream_response, on_result: &emit_chunk(&1, emit)) do
      {:ok, %Response{} = response} -> ResponseNormalizer.normalize(response)
      {:error, _reason} -> {:error, :provider_unavailable}
    end
  rescue
    _error -> {:error, :provider_unavailable}
  catch
    {:vxpipe_emit_failed, _reason} -> {:error, :event_unavailable}
    _kind, _reason -> {:error, :provider_unavailable}
  after
    close_stream(stream_response)
  end

  defp emit_chunk(text, emit) do
    case emit.(text) do
      :ok -> :ok
      {:error, reason} -> throw({:vxpipe_emit_failed, reason})
    end
  end

  defp close_stream(stream_response) do
    StreamResponse.close(stream_response)
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end
end
