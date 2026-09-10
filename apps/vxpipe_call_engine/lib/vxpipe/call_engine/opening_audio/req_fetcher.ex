defmodule Vxpipe.CallEngine.OpeningAudio.ReqFetcher do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.OpeningAudio.Fetcher

  alias Vxpipe.CallEngine.OpeningAudio.{DNSResolver, Download, NetworkAddressPolicy}

  @overflow_key :vxpipe_opening_audio_overflow

  @impl true
  def fetch(url, limits, options) when is_binary(url) and is_list(limits) do
    maximum_bytes = Keyword.fetch!(limits, :maximum_bytes)
    timeout_ms = Keyword.fetch!(limits, :timeout_ms)
    resolver = Keyword.get(options, :resolver, {DNSResolver, []})

    with {:ok, uri} <- URI.new(url),
         {:ok, address} <- resolve(uri.host, resolver, timeout_ms),
         {:ok, response} <- request(uri, address, maximum_bytes, timeout_ms),
         :ok <- response_status(response),
         :ok <- response_size(response, maximum_bytes),
         {:ok, content_type} <- content_type(response) do
      {:ok, %Download{body: response.body, content_type: content_type}}
    else
      _error -> {:error, :download_failed}
    end
  rescue
    _exception -> {:error, :download_failed}
  catch
    :exit, _reason -> {:error, :download_failed}
  end

  defp resolve(host, resolver, timeout_ms) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} ->
        NetworkAddressPolicy.select_public([address])

      {:error, :einval} ->
        task = Task.async(fn -> resolve_host(resolver, host) end)

        case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
          {:ok, {:ok, addresses}} -> NetworkAddressPolicy.select_public(addresses)
          _error -> {:error, :unsafe_address}
        end
    end
  end

  defp resolve_host({module, resolver_options}, host)
       when is_atom(module) do
    module.resolve(host, resolver_options)
  end

  defp request(uri, address, maximum_bytes, timeout_ms) do
    hostname = uri.host
    resolved_url = URI.to_string(%{uri | host: address |> :inet.ntoa() |> List.to_string()})

    Req.get(resolved_url,
      compressed: false,
      connect_options: [hostname: hostname, protocols: [:http1], timeout: timeout_ms],
      decode_body: false,
      headers: [{"accept", "audio/wav, audio/wave, audio/x-wav"}],
      into: bounded_body(maximum_bytes),
      raw: true,
      receive_timeout: timeout_ms,
      redirect: false,
      request_timeout: timeout_ms,
      retry: false
    )
  end

  defp bounded_body(maximum_bytes) do
    fn {:data, data}, {request, response} ->
      if byte_size(response.body) + byte_size(data) <= maximum_bytes do
        {:cont, {request, %{response | body: response.body <> data}}}
      else
        response = put_in(response.private[@overflow_key], true)
        {:halt, {request, response}}
      end
    end
  end

  defp response_status(%Req.Response{status: 200}), do: :ok
  defp response_status(_response), do: {:error, :unexpected_status}

  defp response_size(response, maximum_bytes) do
    content_length =
      response
      |> Req.Response.get_header("content-length")
      |> List.first()
      |> parse_content_length()

    if response.private[@overflow_key] == true or content_length > maximum_bytes do
      {:error, :response_too_large}
    else
      :ok
    end
  end

  defp parse_content_length(nil), do: 0

  defp parse_content_length(value) do
    case Integer.parse(value) do
      {length, ""} when length >= 0 -> length
      _invalid -> 0
    end
  end

  defp content_type(response) do
    case response |> Req.Response.get_header("content-type") |> List.first() do
      value when is_binary(value) ->
        normalized =
          value
          |> String.split(";", parts: 2)
          |> List.first()
          |> String.trim()
          |> String.downcase()

        {:ok, normalized}

      nil ->
        {:error, :missing_content_type}
    end
  end
end
