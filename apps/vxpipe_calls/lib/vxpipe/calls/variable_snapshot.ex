defmodule Vxpipe.Calls.VariableSnapshot do
  @moduledoc "An immutable full Call Variables snapshot accepted for private archival."

  @derive {Inspect, except: [:sections]}
  @attribution_fields [
    :command_id,
    :participant_id,
    :activation_id,
    :source_participant_id,
    :correlation_id,
    :tool_call_id,
    :section,
    :section_revision
  ]
  @required_fields [
    :id,
    :kind,
    :tenant_key,
    :call_id,
    :room_id,
    :incarnation_id,
    :global_revision,
    :sections,
    :source_policy,
    :occurred_at
  ]
  @enforce_keys @required_fields
  defstruct @required_fields ++ @attribution_fields

  @type kind :: :baseline | :update
  @type section_snapshot :: %{revision: non_neg_integer(), value: nil | map()}
  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          tenant_key: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          global_revision: non_neg_integer(),
          sections: %{String.t() => section_snapshot()},
          source_policy: map(),
          occurred_at: DateTime.t(),
          command_id: nil | String.t(),
          participant_id: nil | String.t(),
          activation_id: nil | String.t(),
          source_participant_id: nil | String.t(),
          correlation_id: nil | String.t(),
          tool_call_id: nil | String.t(),
          section: nil | String.t(),
          section_revision: nil | pos_integer()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_variable_snapshot}
  def new(attributes) when is_list(attributes) do
    with {:ok, attributes} <- Keyword.validate(attributes, @required_fields ++ @attribution_fields),
         :ok <- required(attributes),
         :ok <- validate_identity(attributes),
         :ok <- validate_sections(attributes),
         :ok <- validate_kind(attributes),
         {:ok, attributes} <- canonicalize_json(attributes) do
      {:ok, struct!(__MODULE__, attributes)}
    else
      _invalid -> {:error, :invalid_variable_snapshot}
    end
  end

  def new(_attributes), do: {:error, :invalid_variable_snapshot}

  defp required(attributes) do
    if Enum.all?(@required_fields, &Keyword.has_key?(attributes, &1)),
      do: :ok,
      else: {:error, :missing_field}
  end

  defp validate_identity(attributes) do
    fields = [:id, :tenant_key, :call_id, :room_id, :incarnation_id]

    if Enum.all?(fields, fn field ->
         value = Keyword.fetch!(attributes, field)
         is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 256
       end) and match?(%DateTime{}, Keyword.fetch!(attributes, :occurred_at)) and
         is_map(Keyword.fetch!(attributes, :source_policy)) do
      :ok
    else
      {:error, :invalid_identity}
    end
  end

  defp validate_sections(attributes) do
    global_revision = Keyword.fetch!(attributes, :global_revision)
    sections = Keyword.fetch!(attributes, :sections)

    valid_sections? =
      is_map(sections) and
        Enum.all?(sections, fn
          {name, %{revision: revision, value: value}}
          when is_binary(name) and is_integer(revision) and revision >= 0 and
                 (is_nil(value) or is_map(value)) ->
            true

          _invalid ->
            false
        end)

    if is_integer(global_revision) and global_revision >= 0 and valid_sections?,
      do: :ok,
      else: {:error, :invalid_sections}
  end

  defp validate_kind(attributes) do
    case Keyword.fetch!(attributes, :kind) do
      :baseline -> validate_baseline(attributes)
      :update -> validate_update(attributes)
      _invalid -> {:error, :invalid_kind}
    end
  end

  defp validate_baseline(attributes) do
    if Keyword.fetch!(attributes, :global_revision) == 0 and
         Enum.all?(@attribution_fields, &(Keyword.get(attributes, &1) == nil)) do
      :ok
    else
      {:error, :invalid_baseline}
    end
  end

  defp validate_update(attributes) do
    string_fields = Enum.reject(@attribution_fields, &(&1 == :section_revision))
    section_revision = Keyword.get(attributes, :section_revision)

    if Keyword.fetch!(attributes, :global_revision) > 0 and
         is_integer(section_revision) and section_revision > 0 and
         Enum.all?(string_fields, fn field ->
           value = Keyword.get(attributes, field)
           is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 256
         end) do
      :ok
    else
      {:error, :invalid_update}
    end
  end

  defp canonicalize_json(attributes) do
    sections =
      attributes
      |> Keyword.fetch!(:sections)
      |> Map.new(fn {name, section} ->
        {name, %{section | value: canonical_json(section.value)}}
      end)

    canonical =
      attributes
      |> Keyword.put(:sections, sections)
      |> Keyword.put(
        :source_policy,
        attributes |> Keyword.fetch!(:source_policy) |> canonical_json()
      )

    {:ok, canonical}
  rescue
    _error -> {:error, :not_json_safe}
  end

  defp canonical_json(value), do: value |> JSON.encode!() |> JSON.decode!()
end
