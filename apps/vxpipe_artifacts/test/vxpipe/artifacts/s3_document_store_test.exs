defmodule Vxpipe.Artifacts.S3DocumentStoreTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Artifacts.{Document, S3DocumentStore, TestS3DocumentClient}

  @contents ~s({"call":"call-1"})
  @checksum :crypto.hash(:sha256, @contents)
  @object_key "calls/tenant/call/details/details-20260912160100100.json"

  test "conditionally writes exact document bytes and returns a protected reference" do
    assert {:ok, document} = Document.new(@object_key, @contents, @checksum)

    assert {:ok, reference} =
             S3DocumentStore.put(
               document,
               bucket: "call-details-test",
               client: TestS3DocumentClient,
               client_options: [observer: self()]
             )

    assert reference == %{"object_key" => @object_key, "etag" => "etag-document"}

    assert_receive {:test_document_put, "call-details-test", @object_key, @contents, @checksum}
    refute_receive {:test_document_head, _, _}
    refute inspect(reference) =~ "https://"
  end

  test "treats an existing object as an idempotent retry only when its checksum matches" do
    assert {:ok, document} = Document.new(@object_key, @contents, @checksum)

    options = [
      bucket: "call-details-test",
      client: TestS3DocumentClient,
      client_options: [
        observer: self(),
        put_result: {:error, :already_exists},
        head_result: {:ok, %{checksum: @checksum, etag: "etag-existing"}}
      ]
    ]

    assert {:ok, %{"object_key" => @object_key, "etag" => "etag-existing"}} =
             S3DocumentStore.put(document, options)

    assert_receive {:test_document_put, "call-details-test", @object_key, @contents, @checksum}
    assert_receive {:test_document_head, "call-details-test", @object_key}

    conflicting_options =
      put_in(
        options,
        [:client_options, :head_result],
        {:ok, %{checksum: :crypto.hash(:sha256, "different"), etag: "etag-other"}}
      )

    assert {:error, :object_key_conflict} =
             S3DocumentStore.put(document, conflicting_options)
  end

  test "does not report a remote write when the object client fails" do
    assert {:ok, document} = Document.new(@object_key, @contents, @checksum)

    assert {:error, :storage_unavailable} =
             S3DocumentStore.put(
               document,
               bucket: "call-details-test",
               client: TestS3DocumentClient,
               client_options: [
                 observer: self(),
                 put_result: {:error, :storage_unavailable}
               ]
             )
  end
end
