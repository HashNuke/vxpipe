defmodule Vxpipe.Calls.CallArtifact do
  @moduledoc "Terminal metadata and storage reference for one call recording artifact."

  @required_fields [
    :id,
    :tenant_key,
    :call_id,
    :room_id,
    :incarnation_id,
    :kind,
    :object_key,
    :object_reference,
    :sample_rate,
    :channels,
    :sample_format,
    :started_offset_samples,
    :ended_offset_samples,
    :sample_count,
    :accepted_chunks,
    :rejected_chunks,
    :gaps,
    :status,
    :terminal_reason
  ]
  @optional_fields [:participant_id, :connection_id, :track_id]
  @identity_fields [:id, :tenant_key, :call_id, :room_id, :incarnation_id]

  @derive {Inspect, except: [:object_reference]}
  @enforce_keys @required_fields
  defstruct @required_fields ++ @optional_fields

  @type kind :: :full_mix | :participant_track
  @type status :: :complete | :incomplete
  @type t :: %__MODULE__{}

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_call_artifact}
  def new(attributes) when is_list(attributes) do
    with {:ok, attributes} <- Keyword.validate(attributes, @required_fields ++ @optional_fields),
         :ok <- required(attributes),
         {:ok, attributes} <- canonicalize_json(attributes),
         :ok <- validate_identity(attributes),
         :ok <- validate_kind(attributes),
         :ok <- validate_format(attributes),
         :ok <- validate_progress(attributes),
         :ok <- validate_storage(attributes) do
      {:ok, struct!(__MODULE__, attributes)}
    else
      _invalid -> {:error, :invalid_call_artifact}
    end
  end

  def new(_attributes), do: {:error, :invalid_call_artifact}

  defp required(attributes) do
    if Enum.all?(@required_fields, &Keyword.has_key?(attributes, &1)),
      do: :ok,
      else: {:error, :missing_field}
  end

  defp canonicalize_json(attributes) do
    {:ok,
     attributes
     |> Keyword.update!(:gaps, &canonical_json/1)
     |> Keyword.update!(:object_reference, &canonical_json/1)}
  rescue
    _error -> {:error, :not_json_safe}
  end

  defp canonical_json(nil), do: nil
  defp canonical_json(value), do: value |> JSON.encode!() |> JSON.decode!()

  defp validate_identity(attributes) do
    valid? =
      Enum.all?(@identity_fields, fn field ->
        valid_string?(Keyword.fetch!(attributes, field), 256)
      end) and valid_string?(Keyword.fetch!(attributes, :object_key), 1_024)

    if valid?, do: :ok, else: {:error, :invalid_identity}
  end

  defp validate_kind(attributes) do
    participant_id = Keyword.get(attributes, :participant_id)
    connection_id = Keyword.get(attributes, :connection_id)
    track_id = Keyword.get(attributes, :track_id)

    valid? =
      case Keyword.fetch!(attributes, :kind) do
        :full_mix ->
          Enum.all?([participant_id, connection_id, track_id], &is_nil/1)

        :participant_track ->
          Enum.all?([participant_id, connection_id, track_id], &valid_string?(&1, 256))

        _invalid ->
          false
      end

    if valid?, do: :ok, else: {:error, :invalid_kind}
  end

  defp validate_format(attributes) do
    sample_rate = Keyword.fetch!(attributes, :sample_rate)
    channels = Keyword.fetch!(attributes, :channels)

    if is_integer(sample_rate) and sample_rate > 0 and is_integer(channels) and channels > 0 and
         channels <= 8 and Keyword.fetch!(attributes, :sample_format) == :s16le do
      :ok
    else
      {:error, :invalid_format}
    end
  end

  defp validate_progress(attributes) do
    sample_count = Keyword.fetch!(attributes, :sample_count)
    accepted_chunks = Keyword.fetch!(attributes, :accepted_chunks)
    rejected_chunks = Keyword.fetch!(attributes, :rejected_chunks)
    started = Keyword.fetch!(attributes, :started_offset_samples)
    ended = Keyword.fetch!(attributes, :ended_offset_samples)
    gaps = Keyword.fetch!(attributes, :gaps)

    valid? =
      nonnegative?(sample_count) and nonnegative?(accepted_chunks) and
        nonnegative?(rejected_chunks) and offsets?(sample_count, started, ended) and gaps?(gaps)

    if valid?, do: :ok, else: {:error, :invalid_progress}
  end

  defp validate_storage(attributes) do
    object_key = Keyword.fetch!(attributes, :object_key)
    object_reference = Keyword.fetch!(attributes, :object_reference)
    status = Keyword.fetch!(attributes, :status)
    terminal_reason = Keyword.fetch!(attributes, :terminal_reason)

    valid? =
      status in [:complete, :incomplete] and valid_string?(terminal_reason, 256) and
        object_reference?(object_reference, object_key) and
        (status != :complete or is_map(object_reference))

    if valid?, do: :ok, else: {:error, :invalid_storage}
  end

  defp offsets?(0, nil, nil), do: true

  defp offsets?(sample_count, started, ended) do
    sample_count > 0 and nonnegative?(started) and nonnegative?(ended) and ended > started and
      sample_count <= ended - started
  end

  defp gaps?(gaps) when is_list(gaps) do
    Enum.all?(gaps, fn
      %{"offset_samples" => offset, "sample_count" => count} = gap
      when map_size(gap) == 2 ->
        nonnegative?(offset) and is_integer(count) and count > 0

      _invalid ->
        false
    end)
  end

  defp gaps?(_gaps), do: false

  defp object_reference?(nil, _object_key), do: true

  defp object_reference?(%{"object_key" => object_key} = reference, object_key) do
    Map.keys(reference) |> Enum.all?(&(&1 in ["object_key", "etag"])) and
      optional_string?(Map.get(reference, "etag"), 1_024)
  end

  defp object_reference?(_reference, _object_key), do: false

  defp optional_string?(nil, _maximum), do: true
  defp optional_string?(value, maximum), do: valid_string?(value, maximum)

  defp valid_string?(value, maximum),
    do: is_binary(value) and value != "" and byte_size(value) <= maximum

  defp nonnegative?(value), do: is_integer(value) and value >= 0
end
