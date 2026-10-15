defmodule Vxpipe.Gateway.Telephony.CallIngressBackend do
  @moduledoc false

  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot
  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Calls.TelephonyAdmissionClaim
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, IngressIdentity}

  @type context :: term()

  @callback claim_incoming(context(), IngressIdentity.t(), Event.t()) ::
              {:ok, TelephonyAdmissionClaim.t()}
              | {:duplicate, TelephonyAdmissionClaim.t()}
              | {:error, term()}

  @callback start_incoming(context(), TelephonyAdmissionClaim.t(), ConfiguredService.t()) ::
              {:ok, RoomSnapshot.t()} | {:error, term()}

  @callback activate_incoming(
              context(),
              ConfiguredService.t(),
              TelephonyAdmissionClaim.t(),
              RoomSnapshot.t(),
              pid()
            ) :: {:ok, term()} | {:error, term()}

  @callback start_incoming(
              context(),
              TelephonyAdmissionClaim.t(),
              ConfiguredService.t(),
              pid(),
              reference()
            ) ::
              {:ok, RoomSnapshot.t(), reference() | nil} | {:error, term()}
  @callback bind_incoming(context(), TelephonyAdmissionClaim.t(), String.t()) ::
              {:ok, :admit | :cancel, TelephonyAdmissionClaim.t()} | {:error, term()}
  @callback prepare_incoming(
              context(),
              ConfiguredService.t(),
              TelephonyAdmissionClaim.t(),
              RoomSnapshot.t(),
              pid()
            ) ::
              {:ok, term()} | {:error, term()}
  @callback submit_incoming(context(), term()) ::
              {:ok, term()} | {:error, term(), term()} | {:error, term()}
  @callback release_incoming(context(), TelephonyAdmissionClaim.t(), reference()) ::
              :ok | {:error, term()}
  @callback cancel_incoming(context(), TelephonyAdmissionClaim.t(), reference(), atom()) ::
              :ok | {:error, term()}
  @callback end_incoming(context(), ConfiguredService.t(), Event.t(), term(), atom()) :: term()

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
