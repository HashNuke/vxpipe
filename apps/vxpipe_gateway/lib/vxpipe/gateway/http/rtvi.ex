defmodule Vxpipe.Gateway.HTTP.RTVI do
  @moduledoc false

  import Plug.Conn

  alias ExWebRTC.{ICECandidate, SessionDescription}
  alias Vxpipe.Gateway.WebRTC.ConnectionSupervisor

  def init(options) do
    %{
      candidate_gathering_timeout_ms:
        Keyword.get(options, :candidate_gathering_timeout_ms, 1_000),
      ice_servers: Keyword.get(options, :ice_servers, []),
      maximum_audio_packets: Keyword.get(options, :maximum_audio_packets, 500)
    }
  end

  def offer(conn, options) do
    with {:ok, session_id} <- session_id(conn.body_params),
         {:ok, offer} <- offer_description(conn.body_params),
         {:ok, connection_id, answer} <-
           ConnectionSupervisor.accept_offer(session_id, offer, Map.to_list(options)) do
      send_json(conn, 200, %{
        "pc_id" => connection_id,
        "sdp" => answer.sdp,
        "type" => Atom.to_string(answer.type)
      })
    else
      {:error, reason} -> send_offer_error(conn, reason)
    end
  end

  def add_ice_candidates(conn, _options) do
    with {:ok, connection_id} <- required_string(conn.body_params, "pc_id"),
         {:ok, candidates} <- candidates(Map.get(conn.body_params, "candidates")),
         :ok <- ConnectionSupervisor.add_ice_candidates(connection_id, candidates) do
      send_json(conn, 200, %{"status" => "success"})
    else
      {:error, reason} -> send_candidate_error(conn, reason)
    end
  end

  defp session_id(body_params) do
    request_data = Map.get(body_params, "requestData") || Map.get(body_params, "request_data")

    case request_data do
      request_data when is_map(request_data) -> required_string(request_data, "session_id")
      _invalid -> {:error, :invalid_offer}
    end
  end

  defp offer_description(body_params) do
    with {:ok, sdp} <- required_string(body_params, "sdp"),
         "offer" <- Map.get(body_params, "type") do
      {:ok, %SessionDescription{type: :offer, sdp: sdp}}
    else
      _invalid -> {:error, :invalid_offer}
    end
  end

  defp candidates(candidates) when is_list(candidates) do
    Enum.reduce_while(candidates, {:ok, []}, fn candidate, {:ok, parsed} ->
      case candidate(candidate) do
        {:ok, candidate} -> {:cont, {:ok, [candidate | parsed]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  defp candidates(_invalid), do: {:error, :invalid_candidates}

  defp candidate(candidate) when is_map(candidate) do
    with {:ok, value} <- required_string(candidate, "candidate"),
         {:ok, sdp_mid} <- optional_string(candidate, "sdp_mid"),
         {:ok, sdp_m_line_index} <- optional_non_negative_integer(candidate, "sdp_mline_index") do
      {:ok,
       %ICECandidate{
         candidate: value,
         sdp_mid: sdp_mid,
         sdp_m_line_index: sdp_m_line_index
       }}
    end
  end

  defp candidate(_invalid), do: {:error, :invalid_candidates}

  defp required_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _invalid -> {:error, :invalid_offer}
    end
  end

  defp optional_string(map, key) do
    case Map.get(map, key) do
      nil -> {:ok, nil}
      value when is_binary(value) -> {:ok, value}
      _invalid -> {:error, :invalid_candidates}
    end
  end

  defp optional_non_negative_integer(map, key) do
    case Map.get(map, key) do
      nil -> {:ok, nil}
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _invalid -> {:error, :invalid_candidates}
    end
  end

  defp send_offer_error(conn, reason) when reason in [:not_found, :expired] do
    send_error(conn, 401, "invalid_session", "The gateway session is invalid or expired.")
  end

  defp send_offer_error(conn, :already_claimed) do
    send_error(conn, 409, "session_already_claimed", "The gateway session has already been used.")
  end

  defp send_offer_error(conn, :invalid_offer) do
    send_error(conn, 400, "invalid_offer", "The Small WebRTC offer is invalid.")
  end

  defp send_offer_error(conn, _reason) do
    send_error(conn, 503, "connection_start_failed", "The WebRTC connection could not start.")
  end

  defp send_candidate_error(conn, :connection_not_found) do
    send_error(conn, 404, "connection_not_found", "The WebRTC connection does not exist.")
  end

  defp send_candidate_error(conn, _reason) do
    send_error(conn, 400, "invalid_candidates", "The ICE candidates are invalid.")
  end

  defp send_error(conn, status, code, message) do
    send_json(conn, status, %{
      "error" => %{
        "code" => code,
        "message" => message,
        "retryable" => false,
        "details" => %{}
      }
    })
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end
end
