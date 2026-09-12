defmodule Vxpipe.Artifacts.CallDetailsWriterTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Artifacts.{CallDetailsWriter, S3DocumentStore, TestS3DocumentClient}
  alias Vxpipe.Calls.CallDetailsPublication

  @contents ~s({"call":"call-1"})
  @recorded_at ~U[2026-09-12 16:01:00.100Z]
  @published_at ~U[2026-09-12 16:01:02.000Z]

  test "writes one pending publication below its call-owned prefix" do
    publication = publication()

    assert {:ok, object} =
             CallDetailsWriter.write(
               [
                 document_store: S3DocumentStore,
                 document_store_options: [
                   bucket: "call-details-test",
                   client: TestS3DocumentClient,
                   client_options: [observer: self()]
                 ],
                 now: @published_at
               ],
               publication
             )

    encoded_tenant = Base.url_encode64(publication.tenant_key, padding: false)
    encoded_call = Base.url_encode64(publication.call_id, padding: false)

    expected_key =
      "calls/#{encoded_tenant}/#{encoded_call}/details/#{publication.filename}"

    checksum = publication.checksum

    assert object.object_key == expected_key
    assert object.reference == %{"object_key" => expected_key, "etag" => "etag-document"}
    assert object.published_at == @published_at

    assert_receive {:test_document_put, "call-details-test", ^expected_key, @contents, ^checksum}
  end

  defp publication do
    assert {:ok, publication} =
             CallDetailsPublication.new(
               id: "publication-1",
               tenant_key: "tenant-1",
               call_id: "call-1",
               schema_version: "20260912.01",
               source_digest: :crypto.hash(:sha256, "source"),
               recorded_at: @recorded_at,
               filename: "details-20260912160100100.json",
               completeness: :complete,
               checksum: :crypto.hash(:sha256, @contents),
               contents: @contents,
               status: :pending,
               object_key: nil,
               object_reference: nil,
               published_at: nil
             )

    publication
  end
end
