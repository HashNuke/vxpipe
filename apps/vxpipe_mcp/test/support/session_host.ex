defmodule Vxpipe.MCP.Test.SessionHost do
  @moduledoc false

  def start! do
    reference = make_ref()
    name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {__MODULE__, reference}}}

    ExUnit.Callbacks.start_supervised!(
      {DynamicSupervisor, strategy: :one_for_one, name: name},
      id: {__MODULE__, reference}
    )
  end
end
