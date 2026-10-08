defmodule Vxpipe.Console.Test.LiveTelephonyAdapter do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Telephony.Adapter

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Console.Test.LiveTelephonyCallCleanup

  @impl true
  def dial(options, request),
    do: LiveTelephonyCallCleanup.command(provider(options), :dial, options, request)

  @impl true
  def answer(options, request),
    do: LiveTelephonyCallCleanup.command(provider(options), :answer, options, request)

  @impl true
  def decode_webhook(options, webhook) do
    scope = LiveTelephonyCallCleanup.current()
    result = delegate(options, :decode_webhook, webhook)

    case result do
      {:ok, %Event{}} ->
        :ok = LiveTelephonyCallCleanup.observe(scope, provider(options), options, result)

      _ignored ->
        :ok
    end

    result
  end

  @impl true
  def verify_webhook(options, webhook), do: delegate(options, :verify_webhook, webhook)

  @impl true
  def end_leg(options, request), do: delegate(options, :end_leg, request)

  @impl true
  def send_media(options, request), do: delegate(options, :send_media, request)

  @impl true
  def decode_media_message(options, message),
    do: delegate(options, :decode_media_message, message)

  defp delegate(options, operation, argument),
    do: apply(LiveTelephonyCallCleanup.adapter(provider(options)), operation, [options, argument])

  defp provider(options), do: if(Keyword.has_key?(options, :api_key), do: :telnyx, else: :twilio)
end
