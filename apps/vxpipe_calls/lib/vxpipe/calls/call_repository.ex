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

  @callback release_admission(context(), AdmissionClaim.t(), DateTime.t()) ::
              :ok | {:error, term()}

  @callback mark_call_started(context(), AdmissionClaim.t(), String.t(), DateTime.t()) ::
              {:ok, PreparedCall.t()} | {:error, term()}

  @callback mark_call_failed(context(), AdmissionClaim.t(), atom(), DateTime.t()) ::
              {:ok, PreparedCall.t()} | {:error, term()}

  @doc """
  Inserts an incoming call and initial leg atomically after invoking `authorize` inside
  that transaction. Its credential repositories must share the same Repo/dynamic transaction
  context so their locks remain held through insertion and commit. Propagate authorization
  errors without inserting. Existing duplicates do not invoke this new-write callback;
  recover insertion conflicts only after the failed transaction has ended.

  Validate the claim's tenant, canonical service, provider and account against its pinned
  entry participant before lookup or insertion. Scope event/leg uniqueness and lookup by
  tenant, canonical service UUID and provider. Duplicate account/control/leg/session identity
  must match; a new event ID for the same leg returns the original claim. Reject collisions
  with historical unbound legs without adopting their current alias. Lifecycle writes retain
  the same scope and pinned identity checks.
  """
  @callback claim_incoming_telephony(
              context(),
              TelephonyAdmissionClaim.t(),
              (-> {:ok, :authorized} | {:error, term()})
            ) ::
              {:ok, TelephonyAdmissionClaim.t()}
              | {:duplicate, TelephonyAdmissionClaim.t()}
              | {:error, term()}

  @callback mark_incoming_telephony_started(
              context(),
              TelephonyAdmissionClaim.t(),
              String.t(),
              DateTime.t()
            ) :: {:ok, TelephonyAdmissionClaim.t()} | {:error, term()}

  @callback mark_incoming_telephony_failed(
              context(),
              TelephonyAdmissionClaim.t(),
              atom(),
              DateTime.t()
            ) :: {:ok, TelephonyAdmissionClaim.t()} | {:error, term()}
end
