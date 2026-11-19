defmodule Vxpipe.CallEngine.Diagnostics.EngineTeardownTest do
  use ExUnit.Case, async: false

  @tag timeout: 30_000
  test "fresh Engine capacity follows real room workers and unresolved startup teardown" do
    options = %{connection: :standard_io, args: [~c"+S", ~c"2:2", ~c"-pa" | :code.get_path()]}
    peer = start_supervised!(%{id: :engine_peer, start: {:peer, :start_link, [options]}})
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    assert %{retired_workers: 3, fresh_gate: true} =
             :peer.call(
               peer,
               Vxpipe.CallEngine.DiagnosticEngineTeardown,
               :verify,
               [settings],
               20_000
             )
  end
end
