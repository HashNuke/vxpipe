defmodule Vxpipe.Artifacts.S3ObjectReaderTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Artifacts.{S3ObjectReader, TestS3ReadClient}

  test "reads one bounded range from the persisted object reference" do
    object_reference = %{
      "object_key" => "calls/tenant/call/recordings/full-mix.s16le",
      "etag" => "recording-etag"
    }

    options = [
      bucket: "recordings-test",
      client: TestS3ReadClient,
      client_options: [observer: self(), payload: <<0, 1, 2, 3, 4, 5, 6, 7>>]
    ]

    assert {:ok, <<2, 3, 4, 5>>} =
             S3ObjectReader.read_range(object_reference, 2, 5, options)

    assert_receive {:test_s3_range_read, "recordings-test", object_key, 2, 5, "recording-etag"}

    assert object_key == object_reference["object_key"]
  end

  test "rejects malformed references and reads larger than its memory bound" do
    options = [bucket: "recordings-test", client: TestS3ReadClient]

    assert {:error, :invalid_object_reference} =
             S3ObjectReader.read_range(%{"object_key" => ""}, 0, 1, options)

    assert {:error, :read_too_large} =
             S3ObjectReader.read_range(
               %{"object_key" => "recording.s16le"},
               0,
               1_048_576,
               options
             )
  end
end
