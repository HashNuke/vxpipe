defmodule Vxpipe.Calls.CallSpecRepository do
  @moduledoc "Persistence port for immutable call_specs and deployment routes."

  alias Vxpipe.Calls.{CallSpecRevision, ParticipantRoute, TelephonyRoute}

  @type context :: term()

  @callback next_revision(context(), String.t(), String.t()) ::
              {:ok, pos_integer()} | {:error, term()}
  @callback insert_revision(
              context(),
              String.t(),
              CallSpecRevision.t(),
              [ParticipantRoute.t()]
            ) :: {:ok, CallSpecRevision.t()} | {:error, term()}
  @callback fetch_revision(context(), String.t(), String.t(), pos_integer()) ::
              {:ok, CallSpecRevision.t()} | {:error, :not_found}
  @callback fetch_published_revision(context(), String.t(), String.t()) ::
              {:ok, CallSpecRevision.t()} | {:error, :not_found | :call_spec_not_published}
  @callback publish_revision(context(), String.t(), String.t(), pos_integer(), DateTime.t()) ::
              {:ok, CallSpecRevision.t()} | {:error, term()}
  @callback resolve_route(context(), String.t(), String.t()) ::
              {:ok, ParticipantRoute.t()} | {:error, :route_unavailable}
  @callback resolve_telephony_route(
              context(),
              {:tenant, String.t()},
              String.t(),
              String.t()
            ) :: {:ok, TelephonyRoute.t()} | {:error, :route_unavailable}
end
