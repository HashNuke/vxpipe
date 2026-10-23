defmodule Vxpipe.Gateway.CallJoinTokenJSON do
  @moduledoc "Public join-token projections shared by HTTP and MCP."

  def token(issued),
    do: %{token: issued.secret, expires_at: DateTime.to_iso8601(issued.expires_at)}

  def issued(issued),
    do: %{
      call_id: issued.call_id,
      participant_key: issued.participant_key,
      join_token: token(issued)
    }

  def result(issued),
    do:
      Map.merge(token(issued), %{call_id: issued.call_id, participant_key: issued.participant_key})
end
