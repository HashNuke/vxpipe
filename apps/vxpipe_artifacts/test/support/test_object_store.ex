defmodule Vxpipe.Artifacts.TestObjectStore do
  @moduledoc false

  @behaviour Vxpipe.Artifacts.ObjectStore

  def open(spec, options) do
    observer = Keyword.fetch!(options, :observer)
    send(observer, {:test_object_store_opened, self(), spec})

    if Keyword.get(options, :pause_open, false) do
      receive do
        :test_object_store_resume_open -> :ok
      end
    end

    {:ok, %{observer: observer, spec: spec}}
  end

  def write_chunk(session, chunk, options) do
    reference = make_ref()

    if Keyword.get(options, :report_artifact, false) do
      send(session.observer, {:test_artifact_write, self(), reference, session.spec, chunk})
    else
      send(session.observer, {:test_object_store_write, self(), reference, chunk})
    end

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
