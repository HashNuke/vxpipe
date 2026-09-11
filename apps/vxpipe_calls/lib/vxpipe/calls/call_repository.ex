defmodule Vxpipe.Calls.CallRepository do
  @moduledoc "Persistence port for prepared calls and participant admission credentials."

  alias Vxpipe.Calls.{AdmissionClaim, JoinToken, PreparedCall, TelephonyAdmissionClaim}

  @type context :: term()

  @callback insert_prepared_call(context(), PreparedCall.t(), JoinToken.t()) ::
              {:ok, PreparedCall.t(), JoinToken.t()} | {:error, term()}

  @callback fetch_call(context(), String.t(), String.t()) ::
              {:ok, PreparedCall.t()} | {:error, :not_found}

  @callback issue_join_token(
              context(),
              String.t(),
              String.t(),
              String.t(),
              JoinToken.t()
            ) :: {:ok, JoinToken.t()} | {:error, term()}

  @callback claim_join_token(context(), binary(), map(), DateTime.t()) ::
              {:ok, AdmissionClaim.t()} | {:error, term()}

  @callback mark_call_started(context(), AdmissionClaim.t(), String.t(), DateTime.t()) ::
              {:ok, PreparedCall.t()} | {:error, term()}

  @callback mark_call_failed(context(), AdmissionClaim.t(), atom(), DateTime.t()) ::
              {:ok, PreparedCall.t()} | {:error, term()}

  @callback claim_incoming_telephony(context(), TelephonyAdmissionClaim.t()) ::
              {:ok, TelephonyAdmissionClaim.t()}
              | {:duplicate, TelephonyAdmissionClaim.t()}
              | {:error, term()}
end
