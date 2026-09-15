defmodule Vxpipe.Calls.TelephonyServiceRepository do
  @moduledoc """
  Neutral repository port for tenant carrier bindings without credential payloads.

  Registration requires a readable active credential in the same tenant/provider and
  atomically enforces a tenant-local name and globally unique ingress key. Reads expose
  metadata only; callers must resolve current credentials before new provider work.
  """

  alias Vxpipe.Calls.TelephonyService

  @callback register(term(), TelephonyService.t()) ::
              {:ok, TelephonyService.t()} | {:error, atom()}
  @callback fetch(term(), String.t(), String.t()) ::
              {:ok, TelephonyService.t()} | {:error, atom()}
  @callback fetch_by_ingress(term(), String.t()) ::
              {:ok, TelephonyService.t()} | {:error, atom()}
end
