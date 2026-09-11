defmodule Vxpipe.Artifacts.TestObjectStore do
  @moduledoc false

  @behaviour Vxpipe.Artifacts.ObjectStore

  def open(spec, options) do
    observer = Keyword.fetch!(options, :observer)
    send(observer, {:test_object_store_opened, self(), spec})
    {:ok, %{observer: observer, spec: spec}}
  end

  def write_chunk(session, chunk, _options) do
    reference = make_ref()
    send(session.observer, {:test_object_store_write, self(), reference, chunk})

    receive do
      {:test_object_store_continue, ^reference} -> {:ok, session}
    end
  end

  def complete(session, manifest, options) do
    send(session.observer, {:test_object_store_completed, self(), manifest})

    Keyword.get(
      options,
      :complete,
      {:ok, %{object_key: session.spec.object_key, etag: "test-etag"}}
    )
  end
end
