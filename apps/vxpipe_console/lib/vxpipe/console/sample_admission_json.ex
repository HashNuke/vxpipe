defmodule Vxpipe.Console.SampleAdmissionJSON do
  @moduledoc false

  alias Vxpipe.Calls.IssuedJoinToken

  def error_response(:forbidden, _kind), do: {403, "forbidden"}
  def error_response(%{code: :provider_service_forbidden}, _kind), do: {403, "forbidden"}
  def error_response(:invalid_sample_target, _kind), do: {422, "invalid_sample_target"}

  def error_response(reason, _kind)
      when reason in [:sample_spec_conflict, :call_spec_revision_conflict],
      do: {409, "sample_spec_conflict"}

  def error_response(reason, _kind) when reason in [:not_found, :participant_not_found],
    do: {404, "sample_call_not_found"}

  def error_response(reason, _kind)
      when reason in [
             :call_not_joinable,
             :call_unavailable,
             :participant_admission_unavailable,
             :participant_admission_pending,
             :call_ended,
             :hangup_requested
           ], do: {409, "sample_call_unavailable"}

  def error_response(_reason, kind), do: {503, kind <> "_unavailable"}

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
