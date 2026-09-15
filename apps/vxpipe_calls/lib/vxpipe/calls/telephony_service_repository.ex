defmodule Vxpipe.Calls.TelephonyServiceRepository do
  @moduledoc """
  Neutral repository port for tenant carrier bindings and private authentication.

  Registration requires a readable active credential in the same tenant/provider and
  atomically enforces a tenant-local name and globally unique ingress key. `fetch` and
  `fetch_by_ingress` return metadata only; `resolve` returns private authentication for
  the exact active linked credential.
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
  Lock exact tenant services and active linked credentials around a DB-only write callback.

  Each requirement has a name and error path. When it includes a `reference`, compare that
  complete stable identity with the locked service before invoking the callback. Compare every
  supplied reference, including repeated aliases; reuse locks without dropping mismatches.
  Repositories used by the callback must share this repository's transaction context.
  """
  @callback with_active(term(), String.t(), [map()], (-> term())) :: term()
end
