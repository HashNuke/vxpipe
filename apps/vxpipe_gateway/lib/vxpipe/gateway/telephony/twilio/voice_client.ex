defmodule Vxpipe.Gateway.Telephony.Twilio.VoiceClient do
  @moduledoc false

  @default_base_url "https://api.twilio.com/2010-04-01"

  @type form :: [{String.t(), String.t()}]
  @type outcome :: {:accepted, map()} | {:rejected, pos_integer()} | :unknown

  @spec dial(keyword(), String.t(), String.t(), form()) :: outcome()
  def dial(options, account_sid, auth_token, form) do
    request(options, account_sid, auth_token, "/Accounts/#{account_sid}/Calls.json", form)
  end

  @spec end_call(keyword(), String.t(), String.t(), String.t()) :: outcome()
  def end_call(options, account_sid, auth_token, call_sid) do
    request(
      options,
      account_sid,
      auth_token,
      "/Accounts/#{account_sid}/Calls/#{call_sid}.json",
      [{"Status", "completed"}]
    )
  end

  defp request(options, account_sid, auth_token, path, form) do
    with {:ok, base_url} <- base_url(options),
         {:ok, response} <-
           options
           |> Keyword.get(:request_options, [])
           |> Keyword.merge(
             method: :post,
             url: base_url <> path,
             headers: [
               {"accept", "application/json"},
               {"authorization", basic_auth(account_sid, auth_token)}
             ],
             form: form,
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

  defp base_url(options) do
    case Keyword.get(options, :base_url, @default_base_url) do
      value when is_binary(value) and byte_size(value) > 0 ->
        {:ok, String.trim_trailing(value, "/")}

      _invalid ->
        {:error, :invalid_twilio_base_url}
    end
  end

  defp basic_auth(account_sid, auth_token) do
    "Basic " <> Base.encode64(account_sid <> ":" <> auth_token)
  end
end
