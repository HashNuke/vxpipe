defmodule Vxpipe.Providers.Telnyx.VoiceClient do
  @moduledoc false

  @default_base_url "https://api.telnyx.com/v2"

  @type outcome :: {:accepted, map()} | {:rejected, pos_integer()} | :unknown

  @spec dial(keyword(), map()) :: outcome()
  def dial(options, payload), do: request(options, "/calls", payload)

  @spec answer(keyword(), String.t(), map()) :: outcome()
  def answer(options, call_control_id, payload) do
    request(options, "/calls/#{path_segment(call_control_id)}/actions/answer", payload)
  end

  @spec hangup(keyword(), String.t(), map()) :: outcome()
  def hangup(options, call_control_id, payload) do
    request(options, "/calls/#{path_segment(call_control_id)}/actions/hangup", payload)
  end

  defp request(options, path, payload) do
    with {:ok, api_key} <- required_option(options, :api_key),
         {:ok, base_url} <- base_url(options),
         {:ok, response} <-
           options
           |> Keyword.get(:request_options, [])
           |> Keyword.merge(
             method: :post,
             url: base_url <> path,
             auth: {:bearer, api_key},
             headers: [{"accept", "application/json"}],
             json: payload,
             retry: false,
             redirect: false
           )
           |> Req.request() do
      classify(response)
    else
      {:error, _reason} -> :unknown
    end
  rescue
    _exception -> :unknown
  catch
    _kind, _reason -> :unknown
  end

  defp classify(%Req.Response{status: status, body: body})
       when status in 200..299 and is_map(body),
       do: {:accepted, body}

  defp classify(%Req.Response{status: status}) when status in 400..499,
    do: {:rejected, status}

  defp classify(%Req.Response{}), do: :unknown

  defp required_option(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _missing -> {:error, {:missing_telnyx_option, key}}
    end
  end

  defp base_url(options) do
    case Keyword.get(options, :base_url, @default_base_url) do
      value when is_binary(value) and byte_size(value) > 0 ->
        {:ok, String.trim_trailing(value, "/")}

      _invalid ->
        {:error, {:invalid_telnyx_option, :base_url}}
    end
  end

  defp path_segment(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
