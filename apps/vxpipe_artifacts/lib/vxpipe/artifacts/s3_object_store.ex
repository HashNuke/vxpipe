defmodule Vxpipe.Artifacts.S3ObjectStore do
  @moduledoc "Streams bounded PCM buffers through an S3-compatible multipart upload."

  @behaviour Vxpipe.Artifacts.ObjectStore

  alias Vxpipe.Artifacts.{ArtifactSpec, Chunk, Manifest, S3Client}
  alias Vxpipe.Artifacts.S3ObjectStore.Session

  @minimum_part_size_bytes 5 * 1_024 * 1_024

  @impl true
  def open(%ArtifactSpec{} = spec, options) when is_list(options) do
    with {:ok, bucket} <- nonempty(options, :bucket),
         {:ok, client} <- client(options),
         {:ok, client_options} <- keyword(options, :client_options, []),
         {:ok, part_size_bytes} <- part_size(options),
         {:ok, upload_id} <- client.initiate(bucket, spec.object_key, client_options) do
      {:ok,
       %Session{
         spec: spec,
         bucket: bucket,
         client: client,
         client_options: client_options,
         upload_id: upload_id,
         part_size_bytes: part_size_bytes,
         buffer: [],
         buffer_bytes: 0,
         parts: [],
         next_part_number: 1
       }}
    end
  end

  def open(_spec, _options), do: {:error, :invalid_s3_options}

  @impl true
  def write_chunk(%Session{} = session, %Chunk{} = chunk, _options) do
    session = %{
      session
      | buffer: [chunk.payload | session.buffer],
        buffer_bytes: session.buffer_bytes + byte_size(chunk.payload)
    }

    if session.buffer_bytes >= session.part_size_bytes,
      do: upload_buffer(session),
      else: {:ok, session}
  end

  def write_chunk(_session, _chunk, _options), do: {:error, :invalid_s3_session}

  @impl true
  def complete(%Session{} = session, %Manifest{}, _options) do
    with {:ok, session} <- upload_final_buffer(session),
         true <- session.parts != [],
         parts = Enum.reverse(session.parts),
         {:ok, artifact} <-
           session.client.complete(
             session.bucket,
             session.spec.object_key,
             session.upload_id,
             parts,
             session.client_options
           ) do
      {:ok, artifact}
    else
      false -> abort(session, :empty_recording)
      {:error, reason} -> abort(session, reason)
    end
  end

  def complete(_session, _manifest, _options), do: {:error, :invalid_s3_session}

  defp upload_final_buffer(%Session{buffer_bytes: 0} = session), do: {:ok, session}
  defp upload_final_buffer(session), do: upload_buffer(session)

  defp upload_buffer(session) do
    payload = session.buffer |> Enum.reverse() |> IO.iodata_to_binary()

    case session.client.upload_part(
           session.bucket,
           session.spec.object_key,
           session.upload_id,
           session.next_part_number,
           payload,
           session.client_options
         ) do
      {:ok, etag} when is_binary(etag) and etag != "" ->
        {:ok,
         %{
           session
           | buffer: [],
             buffer_bytes: 0,
             parts: [{session.next_part_number, etag} | session.parts],
             next_part_number: session.next_part_number + 1
         }}

      {:error, reason} ->
        {:error, reason}

      _invalid ->
        {:error, :invalid_upload_part_response}
    end
  end

  defp abort(session, reason) do
    _outcome =
      session.client.abort(
        session.bucket,
        session.spec.object_key,
        session.upload_id,
        session.client_options
      )

    {:error, reason}
  end

  defp client(options) do
    case Keyword.get(options, :client, Vxpipe.Artifacts.ExAwsS3Client) do
      client when is_atom(client) ->
        if S3Client.valid?(client), do: {:ok, client}, else: {:error, :invalid_s3_client}

      _invalid ->
        {:error, :invalid_s3_client}
    end
  end

  defp part_size(options) do
    case Keyword.get(options, :part_size_bytes, @minimum_part_size_bytes) do
      value when is_integer(value) and value >= @minimum_part_size_bytes -> {:ok, value}
      _invalid -> {:error, :invalid_s3_part_size}
    end
  end

  defp keyword(options, key, default) do
    case Keyword.get(options, key, default) do
      value when is_list(value) -> {:ok, value}
      _invalid -> {:error, :invalid_s3_options}
    end
  end

  defp nonempty(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, :invalid_s3_options}
    end
  end
end
