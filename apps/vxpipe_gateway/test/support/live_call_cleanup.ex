defmodule Vxpipe.Gateway.TestLiveCallCleanup do
  @moduledoc "Handle-scoped carrier teardown for live tests, independent of room shutdown."

  @terminal_states ~w(canceled completed failed busy no-answer)

  def hangup(provider, options, handle) when provider in [:telnyx, :twilio] do
    case status(provider, options, handle) do
      :ended ->
        :ok

      {:active, target} ->
        _result = end_call(provider, options, handle, target)

        case status(provider, options, handle) do
          :ended -> :ok
          {:active, _target} -> failure(provider, :still_active)
          :unverified -> failure(provider, :unverified)
        end

      :unverified ->
        failure(provider, :unverified)
    end
  rescue
    _exception -> failure(provider, :unverified)
  catch
    :exit, _reason -> failure(provider, :unverified)
  end

  defp status(:telnyx, options, handle) do
    case request(:telnyx, options, handle, method: :get) do
      {:ok, %Req.Response{status: 200, body: %{"data" => %{"is_alive" => false}}}} ->
        :ended

      {:ok, %Req.Response{status: 200, body: %{"data" => %{"is_alive" => true}}}} ->
        {:active, :hangup}

      _unverified ->
        :unverified
    end
  end

  defp status(:twilio, options, handle) do
    case request(:twilio, options, handle, method: :get) do
      {:ok, %Req.Response{status: 200, body: %{"sid" => ^handle, "status" => state}}}
      when state in @terminal_states ->
        :ended

      {:ok, %Req.Response{status: 200, body: %{"sid" => ^handle, "status" => "in-progress"}}} ->
        {:active, "completed"}

      {:ok, %Req.Response{status: 200, body: %{"sid" => ^handle, "status" => state}}}
      when state in ["queued", "ringing"] ->
        {:active, "canceled"}

      _unverified ->
        :unverified
    end
  end

  defp end_call(:telnyx, options, handle, :hangup),
    do: request(:telnyx, options, handle, method: :post, suffix: "/actions/hangup", json: %{})

  defp end_call(:twilio, options, handle, target),
    do: request(:twilio, options, handle, method: :post, form: [{"Status", target}])

  defp request(provider, options, handle, request) do
    {base_url, auth} = endpoint(provider, options)
    suffix = Keyword.get(request, :suffix, "")
    url = base_url <> URI.encode(handle, &URI.char_unreserved?/1) <> suffix
    url = if provider == :twilio, do: url <> ".json", else: url

    options
    |> Keyword.get(:request_options, [])
    |> Keyword.merge(Keyword.delete(request, :suffix))
    |> Keyword.merge(
      url: url,
      auth: auth,
      retry: false,
      redirect: false,
      receive_timeout: 5_000,
      connect_options: [timeout: 5_000]
    )
    |> Req.request()
  end

  defp endpoint(:telnyx, options),
    do: {"https://api.telnyx.com/v2/calls/", {:bearer, Keyword.fetch!(options, :api_key)}}

  defp endpoint(:twilio, options) do
    account = Keyword.fetch!(options, :account_sid)
    auth = {:basic, account <> ":" <> Keyword.fetch!(options, :auth_token)}
    {"https://api.twilio.com/2010-04-01/Accounts/#{account}/Calls/", auth}
  end

  defp failure(provider, reason), do: {:error, {:live_call_cleanup, provider, reason}}
end
