defmodule Vxpipe.Calls.DemoTenantRepository do
  @moduledoc "Persistence port for one installation's durable demo-tenant binding."

  alias Vxpipe.Calls.Tenant

  @type context :: term()

  @callback ensure(context(), Tenant.t()) :: {:ok, Tenant.t()} | {:error, term()}
end
