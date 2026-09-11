defmodule Vxpipe.Gateway.Telephony.CallIngressBackend do
  @moduledoc false

  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot
  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Calls.TelephonyAdmissionClaim
  alias Vxpipe.Gateway.Telephony.IngressIdentity

  @type context :: term()

  @callback claim_incoming(context(), IngressIdentity.t(), Event.t()) ::
              {:ok, TelephonyAdmissionClaim.t()}
              | {:duplicate, TelephonyAdmissionClaim.t()}
              | {:error, term()}

  @callback start_incoming(context(), TelephonyAdmissionClaim.t()) ::
              {:ok, RoomSnapshot.t()} | {:error, term()}

  @callback activate_incoming(
              context(),
              IngressIdentity.t(),
              TelephonyAdmissionClaim.t(),
              RoomSnapshot.t(),
              pid()
            ) :: {:ok, term()} | {:error, term()}

  @callback mark_incoming_started(
              context(),
              TelephonyAdmissionClaim.t(),
              String.t(),
              DateTime.t()
            ) :: {:ok, TelephonyAdmissionClaim.t()} | {:error, term()}

  @callback mark_incoming_failed(context(), TelephonyAdmissionClaim.t(), atom()) ::
              {:ok, TelephonyAdmissionClaim.t()} | {:error, term()}

  @callback handle_live_event(context(), TelephonyAdmissionClaim.t(), term(), pid(), Event.t()) ::
              :ok | {:error, term()}
end
