defmodule Vxpipe.Gateway.TestTelephonyAdapter do
  @behaviour Vxpipe.CallEngine.Telephony.Adapter

  alias Vxpipe.CallEngine.Telephony.{Submission, Webhook}

  @impl true
  def answer(options, request) do
    send(observer(options), {:test_telephony_answer, request})

    case Keyword.fetch!(options, :api_key) do
      "reject" ->
        {:error, :command_rejected}

      _accepted ->
        {:ok,
         %Submission{
           status: :accepted,
           provider_call_control_id: request.leg.provider_call_control_id
         }}
    end
  end

  @impl true
  def dial(options, request) do
    send(observer(options), {:test_telephony_dial, request})

    case Keyword.fetch!(options, :api_key) do
      "blocked:" <> _observer ->
        send(observer(options), {:test_telephony_dial_pending, self()})

        receive do
          :release_test_telephony_dial ->
            {:ok,
             %Submission{
               status: :accepted,
               provider_call_control_id: "outbound-call-control",
               provider_call_leg_id: "outbound-call-leg",
               provider_call_session_id: "outbound-call-session"
             }}
        end

      "unknown:" <> _observer ->
        {:ok, %Submission{status: :unknown, provider_call_control_id: nil}}

      "reject:" <> _observer ->
        {:error, :command_rejected}

      _accepted ->
        {:ok,
         %Submission{
           status: :accepted,
           provider_call_control_id: "outbound-call-control",
           provider_call_leg_id: "outbound-call-leg",
           provider_call_session_id: "outbound-call-session"
         }}
    end
  end

  @impl true
  def send_media(_options, _request), do: {:error, :not_supported}

  @impl true
  def end_leg(options, request) do
    send(observer(options), {:test_telephony_end_leg, request})

    {:ok,
     %Submission{
       status: :accepted,
       provider_call_control_id: request.leg.provider_call_control_id
     }}
  end

  @impl true
  def verify_webhook(_options, %Webhook{}), do: :ok

  @impl true
  def decode_webhook(_options, %Webhook{}), do: :ignore

  @impl true
  def decode_media_message(_options, _message), do: :ignore

  defp observer(options) do
    case Keyword.fetch!(options, :api_key) do
      "observer:" <> encoded -> encoded |> String.to_charlist() |> :erlang.list_to_pid()
      "unknown:" <> encoded -> encoded |> String.to_charlist() |> :erlang.list_to_pid()
      "reject:" <> encoded -> encoded |> String.to_charlist() |> :erlang.list_to_pid()
      "blocked:" <> encoded -> encoded |> String.to_charlist() |> :erlang.list_to_pid()
      _other -> self()
    end
  end
end
