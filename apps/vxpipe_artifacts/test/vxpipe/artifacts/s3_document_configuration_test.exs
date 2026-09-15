defmodule Vxpipe.Artifacts.S3DocumentConfigurationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Artifacts.S3DocumentConfiguration

  test "builds document-store options for an S3-compatible target" do
    assert {:ok, options} =
             S3DocumentConfiguration.build(
               bucket: "call-artifacts",
               region: "us-east-1",
               endpoint: "http://object-store.internal:9000"
             )

    assert Keyword.fetch!(options, :bucket) == "call-artifacts"

    assert Keyword.fetch!(options, :client_options) ==
             [
               request_options: [
                 region: "us-east-1",
                 scheme: "http://",
                 host: "object-store.internal",
                 port: 9000,
                 virtual_host: false
               ]
             ]
  end

  test "requires a bucket and rejects non-root or credential-bearing endpoints" do
    assert {:error, :document_bucket_required} = S3DocumentConfiguration.build([])

    for endpoint <- [
          "https://object-store.internal:9000/a/path",
          "https://user:secret@object-store.internal:9000",
          "file:///tmp/objects"
        ] do
      assert {:error, :invalid_document_endpoint} =
               S3DocumentConfiguration.build(bucket: "call-artifacts", endpoint: endpoint)
    end
  end

  test "omits optional request configuration" do
    assert {:ok, [bucket: "call-artifacts", client_options: [request_options: []]]} =
             S3DocumentConfiguration.build(bucket: "call-artifacts")
  end

  test "rejects invalid endpoint ports before a document request can start" do
    for port <- ["bad", "-1", "0", "65536", "99999"] do
      assert {:error, :invalid_document_endpoint} =
               S3DocumentConfiguration.build(
                 bucket: "call-artifacts",
                 endpoint: "http://objects.example.test:" <> port
               )
    end
  end
end
