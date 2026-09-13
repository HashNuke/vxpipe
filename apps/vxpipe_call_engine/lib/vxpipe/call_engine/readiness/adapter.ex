defmodule Vxpipe.CallEngine.Readiness.Adapter do
  @moduledoc """
  Operational readiness at the boundary that owns a resource.

  Implementations return an opaque configuration signature and the actual live generation.
  They must use their initialization/connection evidence, never PID existence as readiness.
  The lifecycle collector associates each bounded response with its barrier request before
  creating a report. Calls belong outside the room authority's receive loop.
  """

  alias Vxpipe.CallEngine.Readiness.{Report, Resource}

  @callback readiness(GenServer.server()) ::
              {:ok, Resource.t(), Report.status()} | {:error, :unavailable}
end
