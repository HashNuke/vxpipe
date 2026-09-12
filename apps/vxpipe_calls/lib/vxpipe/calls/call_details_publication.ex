defmodule Vxpipe.Calls.CallDetailsPublication do
  @moduledoc "One persisted immutable call-details revision and its delivery state."

  alias Vxpipe.Calls.{CallDetailsObject, CallDetailsSnapshot}

  @fields [
    :id,
    :tenant_key,
    :call_id,
    :schema_version,
    :source_digest,
    :recorded_at,
    :filename,
    :completeness,
    :checksum,
    :contents,
    :status,
    :object_key,
    :object_reference,
    :published_at
  ]

  @derive {Inspect, except: [:source_digest, :checksum, :contents, :object_reference]}
  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_key: String.t(),
          call_id: String.t(),
          schema_version: String.t(),
          source_digest: binary(),
          recorded_at: DateTime.t(),
          filename: String.t(),
          completeness: :complete | :incomplete,
          checksum: binary(),
          contents: binary(),
          status: :pending | :published,
          object_key: String.t() | nil,
          object_reference: map() | nil,
          published_at: DateTime.t() | nil
        }

  @spec pending(String.t(), String.t(), CallDetailsSnapshot.t()) ::
          {:ok, t()} | {:error, :invalid_call_details_publication}
  def pending(tenant_key, call_id, %CallDetailsSnapshot{} = snapshot) do
    new(
      id: snapshot.publication_id,
      tenant_key: tenant_key,
      call_id: call_id,
      schema_version: snapshot.schema_version,
      source_digest: snapshot.source_digest,
      recorded_at: snapshot.recorded_at,
      filename: snapshot.filename,
      completeness: snapshot.completeness,
      checksum: snapshot.checksum,
      contents: snapshot.contents,
      status: :pending,
      object_key: nil,
      object_reference: nil,
      published_at: nil
    )
  end

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_call_details_publication}
  def new(attributes) when is_list(attributes) do
    with {:ok, attributes} <- Keyword.validate(attributes, @fields),
         true <- Enum.all?(@fields, &Keyword.has_key?(attributes, &1)),
         publication = struct!(__MODULE__, attributes),
         true <- valid?(publication) do
      {:ok, publication}
    else
      _invalid -> {:error, :invalid_call_details_publication}
    end
  end

  def new(_attributes), do: {:error, :invalid_call_details_publication}

  @spec publish(t(), CallDetailsObject.t()) ::
          {:ok, t()} | {:error, :publication_receipt_conflict}
  def publish(%__MODULE__{status: :pending} = publication, %CallDetailsObject{} = object) do
    if String.ends_with?(object.object_key, "/" <> publication.filename) do
      {:ok,
       %{
         publication
         | status: :published,
           object_key: object.object_key,
           object_reference: object.reference,
           published_at: object.published_at
       }}
    else
      {:error, :publication_receipt_conflict}
    end
  end

  def publish(%__MODULE__{status: :published} = publication, %CallDetailsObject{} = object) do
    if publication.object_key == object.object_key and
         publication.object_reference == object.reference and
         DateTime.compare(publication.published_at, object.published_at) == :eq,
       do: {:ok, publication},
       else: {:error, :publication_receipt_conflict}
  end

  defp valid?(publication) do
    valid_string?(publication.id, 256) and valid_string?(publication.tenant_key, 64) and
      valid_string?(publication.call_id, 256) and valid_string?(publication.schema_version, 32) and
      valid_digest?(publication.source_digest) and valid_digest?(publication.checksum) and
      is_binary(publication.contents) and byte_size(publication.contents) > 0 and
      :crypto.hash(:sha256, publication.contents) == publication.checksum and
      valid_record?(publication) and valid_delivery?(publication)
  end

  defp valid_record?(publication) do
    is_struct(publication.recorded_at, DateTime) and utc?(publication.recorded_at) and
      valid_string?(publication.filename, 64) and
      Regex.match?(~r/^details-\d{17}\.json$/, publication.filename) and
      publication.completeness in [:complete, :incomplete] and
      publication.status in [:pending, :published]
  end

  defp valid_delivery?(%__MODULE__{status: :pending} = publication) do
    is_nil(publication.object_key) and is_nil(publication.object_reference) and
      is_nil(publication.published_at)
  end

  defp valid_delivery?(%__MODULE__{status: :published} = publication) do
    match?(
      {:ok, %CallDetailsObject{}},
      CallDetailsObject.new(
        publication.object_key,
        publication.object_reference,
        publication.published_at
      )
    )
  end

  defp valid_string?(value, maximum),
    do: is_binary(value) and value != "" and byte_size(value) <= maximum

  defp valid_digest?(value), do: is_binary(value) and byte_size(value) == 32

  defp utc?(value), do: value.utc_offset == 0 and value.std_offset == 0
end
