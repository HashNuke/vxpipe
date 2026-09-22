defmodule Vxpipe.CallEngine.Speech.CallLoadIngressObserverTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.CallLoad.IngressObserver

  test "missing observation stays unknown while deliveries and drops are counted per ingress" do
    probe = start_supervised!(IngressObserver)
    assert IngressObserver.stats(probe, self()) == nil
    send(probe, {:vxpipe_media_ingress, self(), {:delivered, 1}})
    send(probe, {:vxpipe_media_ingress, self(), {:dropped, :stale, 2}})
    assert IngressObserver.stats(probe, self()) == %{delivered: 1, dropped: 1}
  end
end
