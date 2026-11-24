defmodule Vxpipe.Gateway.TestTelephonyAdapter do
  @behaviour Vxpipe.CallEngine.Telephony.Adapter

  alias Vxpipe.CallEngine.Telephony.{Submission, Webhook}

  @impl true
  def answer(options, request) do
    send(observer(options), {:test_telephony_answer, request})

    case Keyword.fetch!(options, :api_key) do
      "reject" ->
        {:error, :command_rejected}

      "unknown" ->
        {:ok, %Submission{status: :unknown, provider_call_control_id: nil}}

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
    report_owner_monitors(options, :dial)
    send(observer(options), {:test_telephony_dial, request})

    case Keyword.fetch!(options, :api_key) do
      "blocked:" <> _observer ->
        send(observer(options), {:test_telephony_dial_pending, self()})

        receive do
          :release_test_telephony_dial_unknown ->
            {:ok, %Submission{status: :unknown, provider_call_control_id: nil}}

          :release_test_telephony_dial ->
            {:ok,
             %Submission{
               status: :accepted,
               provider_call_control_id: "outbound-call-control",
               provider_call_leg_id: "outbound-call-leg",
               provider_call_session_id: "outbound-call-session"
             }}
        end

      "control-only:" <> _observer ->
        {:ok, %Submission{status: :accepted, provider_call_control_id: "outbound-call-control"}}

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
  def play_recovery_prompt(options, control_id, command_id) do
    send(observer(options), {:test_recovery_playback, control_id, command_id})

    accepted = {:ok, %Submission{status: :accepted, provider_call_control_id: control_id}}

    if String.starts_with?(Keyword.fetch!(options, :api_key), "blocked-playback:") do
      send(observer(options), {:test_playback_in_flight, self()})

      receive do
        :release_playback ->
          accepted

        :reject_playback ->
          {:error, {:telnyx_command_rejected, 422}}

        :unknown_playback ->
          {:ok, %Submission{status: :unknown, provider_call_control_id: control_id}}
      end
    else
      accepted
    end
  end

  @impl true
  def play_recovery_prompt(options, control_id, command_id, :transfer) do
    send(observer(options), {:test_transfer_announcement, control_id, command_id})
    {:ok, %Submission{status: :accepted, provider_call_control_id: control_id}}
  end

  def play_recovery_prompt(options, control_id, command_id, :callback),
    do: play_recovery_prompt(options, control_id, command_id)

  @impl true
  def dial_recovery_peer(options, request) do
    send(observer(options), {:test_linked_dial, request})

    {:ok,
     %Submission{
       status: :accepted,
       provider_call_control_id: "peer-control",
       provider_call_leg_id: "peer-leg",
       provider_call_session_id: "inbound-call-session"
     }}
  end

  @impl true
  def end_leg(options, request) do
    report_owner_monitors(options, :end)
    send(observer(options), {:test_telephony_end_leg, request})

    case Keyword.fetch!(options, :api_key) do
      "blocked-end:" <> _ ->
        send(observer(options), {:test_telephony_end_pending, self()})

        receive do
          :unknown_test_telephony_end ->
            {:ok, %Submission{status: :unknown, provider_call_control_id: nil}}

          :reject_test_telephony_end ->
            {:error, :command_rejected}

          :accept_test_telephony_end ->
            {:ok,
             %Submission{
               status: :accepted,
               provider_call_control_id: request.leg.provider_call_control_id
             }}
        end

      _ ->
        {:ok,
         %Submission{
           status: :accepted,
           provider_call_control_id: request.leg.provider_call_control_id
         }}
    end
  end

  @impl true
  def verify_webhook(_options, %Webhook{}), do: :ok

  @impl true
  def decode_webhook(_options, %Webhook{}), do: :ignore

  @impl true
  def decode_media_message(_options, _message), do: :ignore

  defp report_owner_monitors(options, kind) do
    if owner = Keyword.get(options, :probe_owner_monitors) do
      {:monitors, monitors} = Process.info(owner, :monitors)
      send(owner, {:command_owner_monitors, kind, monitors})
    end
  end

  defp observer(options) do
    case Keyword.fetch!(options, :api_key) do
      "observer:" <> encoded -> encoded |> String.to_charlist() |> :erlang.list_to_pid()
      "unknown:" <> encoded -> encoded |> String.to_charlist() |> :erlang.list_to_pid()
      "reject:" <> encoded -> encoded |> String.to_charlist() |> :erlang.list_to_pid()
      "control-only:" <> encoded -> encoded |> String.to_charlist() |> :erlang.list_to_pid()
      "blocked-playback:" <> encoded -> encoded |> String.to_charlist() |> :erlang.list_to_pid()
      "blocked-end:" <> encoded -> encoded |> String.to_charlist() |> :erlang.list_to_pid()
      "blocked:" <> encoded -> encoded |> String.to_charlist() |> :erlang.list_to_pid()
      _other -> self()
    end
  end
end
