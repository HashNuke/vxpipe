defmodule Vxpipe.Calls.TelephonyServiceRepository do
  @moduledoc """
  Neutral repository port for tenant carrier bindings and private authentication.

  Registration requires readable credentials and atomically enforces tenant-local names
  and globally unique ingress keys. Legacy bindings pin an exact tenant credential;
  scoped Telnyx applications resolve the consuming tenant's effective primary binding.
  Scoped application IDs are unique. `fetch` and `fetch_by_ingress` return stored
  metadata only; `resolve` fills the selected credential identity and authentication.
  Metadata for a scoped application has a credential name but no resolved ID or key.
  """

  alias Vxpipe.Calls.{ResolvedTelephonyService, TelephonyService}

  @callback register(term(), TelephonyService.t()) ::
              {:ok, TelephonyService.t()} | {:error, atom()}
  @callback fetch(term(), String.t(), String.t()) ::
              {:ok, TelephonyService.t()} | {:error, atom()}
  @callback fetch_by_ingress(term(), String.t()) ::
              {:ok, TelephonyService.t()} | {:error, atom()}
  @callback resolve(term(), String.t(), String.t()) ::
              {:ok, ResolvedTelephonyService.t()} | {:error, atom()}

  @doc """
  Lock tenant services and selected credentials around a DB-only write callback.

  Each requirement has a name and error path. When it includes a `reference`, compare that
  complete stable identity with the locked service before invoking the callback. Compare every
  supplied reference, including repeated aliases; reuse locks without dropping mismatches.
  Repositories used by the callback must share this repository's transaction context.
  """
  @callback with_active(term(), String.t(), [map()], (-> term())) :: term()
end
