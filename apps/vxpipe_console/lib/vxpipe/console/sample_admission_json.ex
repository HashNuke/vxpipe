defmodule Vxpipe.Console.SampleAdmissionJSON do
  @moduledoc false

  alias Vxpipe.Calls.IssuedJoinToken

  @spec render(IssuedJoinToken.t()) :: map()
  def render(%IssuedJoinToken{} = token) do
    %{
      "tenant_key" => token.tenant_key,
      "call_id" => token.call_id,
      "participant_key" => token.participant_key,
      "join_token" => %{
        "token" => token.secret,
        "expires_at" => DateTime.to_iso8601(token.expires_at)
      }
    }
  end
end
