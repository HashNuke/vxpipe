defmodule Vxpipe.Persistence.Repo.Migrations.MigrateCallSpecEntrySettings do
  use Ecto.Migration

  @legacy "20260915.01"
  @directional "20261004.01"
  @current "20261125.01"
  @route_fields ~w(audio_routes transcript_routes)
  @flags ~w(record_audio save_transcripts)

  def up do
    table =
      if prefix(),
        do: ~s("#{String.replace(prefix(), "\"", "\"\"")}".call_spec_revisions),
        else: "call_spec_revisions"

    # Keep the set of revisions stable until the migration transaction commits.
    repo().query!("LOCK TABLE #{table} IN SHARE ROW EXCLUSIVE MODE", [], log: false)
    migrate_batch(repo(), table, 0)
  end

  def down do
    raise Ecto.MigrationError,
          "Entry settings were consolidated into call defaults. Restore the pre-migration database backup to recover the original sources."
  end

  defp migrate_batch(repo, table, after_id) do
    rows =
      repo.query!(
        """
        SELECT id, call_spec_id, revision, schema_version, source, compiled_metadata, validation_errors
        FROM #{table} WHERE id > $1 AND
          (schema_version IS DISTINCT FROM $2 OR (source->>'schema_version') IS DISTINCT FROM $2)
        ORDER BY id LIMIT 100
        """,
        [after_id, @current],
        log: false
      ).rows

    Enum.each(rows, &migrate_revision(repo, table, &1))

    case List.last(rows) do
      nil -> :ok
      [last_id | _] -> migrate_batch(repo, table, last_id)
    end
  end

  defp migrate_revision(repo, table, [id, spec_id, revision, version, source, metadata, errors]) do
    check!(version in [@legacy, @directional], "unsupported stored schema version")

    check!(
      is_map(source) and source["schema_version"] == version,
      "source and stored schema versions disagree"
    )

    check!(is_map(metadata), "compiled_metadata must be an object")
    {source, direction, entry_key, handler} = direction(source, version)
    participants = object!(source["participants"], "participants")
    entry = object!(participants[entry_key], "entry participant")

    check!(
      entry["type"] == "human" and is_map(participants[handler]) and entry_key != handler,
      "invalid entry or handler participant"
    )

    if version == @legacy do
      check!(
        match?(%{"mode" => "receive", "admission" => "start_call"}, entry["connection"]),
        "legacy entry connection is not an incoming start-call connection"
      )
    end

    entry_capabilities = object!(Map.get(entry, "capabilities", %{}), "entry capabilities")

    check!(
      Map.keys(entry_capabilities) -- ["speech_to_text"] == [],
      "unsupported dedicated entry capability"
    )

    migrated =
      source
      |> put_in(["participants", entry_key], Map.drop(entry, ["capabilities", "while_present"]))
      |> lift_default("speech_to_text", entry_capabilities["speech_to_text"])
      |> opening(errors)
      |> media_policy(entry)
      |> Map.put("schema_version", @current)

    updated_metadata =
      metadata |> Map.put("schema_version", @current) |> Map.put("direction", direction)

    digest = :crypto.hash(:sha256, JSON.encode!(migrated)) |> Base.encode16(case: :lower)

    repo.query!(
      "UPDATE #{table} SET source=$1, source_digest=$2, schema_version=$3, compiled_metadata=$4 WHERE id=$5",
      [migrated, digest, @current, updated_metadata, id],
      log: false
    )
  catch
    {:incompatible, reason} ->
      raise "call_spec_id=#{spec_id} revision=#{revision} (row #{id}): #{reason}"
  end

  defp direction(source, @legacy) do
    check!(
      not Map.has_key?(source, "incoming_call") and not Map.has_key?(source, "outgoing_call"),
      "legacy source has conflicting direction fields"
    )

    caller = source["entry_caller"]
    handler = source["entry_receiver"]
    check!(is_binary(caller) and is_binary(handler), "missing legacy entry references")

    migrated =
      source
      |> Map.drop(["entry_caller", "entry_receiver"])
      |> Map.put("incoming_call", %{"caller" => caller, "handled_by" => handler})

    {migrated, "incoming", caller, handler}
  end

  defp direction(source, @directional) do
    case {Map.fetch(source, "incoming_call"), Map.fetch(source, "outgoing_call")} do
      {{:ok, %{"caller" => caller, "handled_by" => handler}}, :error}
      when is_binary(caller) and is_binary(handler) ->
        {source, "incoming", caller, handler}

      {:error, {:ok, %{"callee" => callee, "handled_by" => handler}}}
      when is_binary(callee) and is_binary(handler) ->
        {source, "outgoing", callee, handler}

      _ ->
        throw({:incompatible, "expected exactly one call direction with entry references"})
    end
  end

  defp opening(%{"opening_audio" => %{"type" => "text"} = opening} = source, errors) do
    defaults = default_capabilities(source)
    explicit_voice = opening["text_to_speech"]

    if errors == [] do
      check!(
        is_nil(defaults["speech_to_speech"]),
        "text opening is incompatible with speech-to-speech call defaults"
      )

      check!(
        is_map(defaults["text_to_speech"] || explicit_voice),
        "text opening has no usable voice"
      )

      if is_nil(defaults["text_to_speech"]) do
        native_agent? =
          Enum.any?(source["participants"], fn {_key, participant} ->
            is_map(participant) and participant["type"] == "agent" and
              not is_nil(get_in(participant, ["capabilities", "speech_to_speech"]))
          end)

        check!(
          not native_agent?,
          "inheriting the opening voice would conflict with a speech-to-speech agent"
        )
      end
    end

    source
    |> lift_default("text_to_speech", explicit_voice)
    |> Map.put("opening_audio", Map.delete(opening, "text_to_speech"))
  end

  defp opening(source, _errors), do: source

  defp lift_default(source, _kind, nil), do: source

  defp lift_default(source, kind, selection) do
    capabilities = default_capabilities(source)

    if Map.has_key?(capabilities, kind) do
      source
    else
      check!(is_map(selection), "inline capability selection must be an object")
      defaults = Map.get(source, "defaults", %{})

      Map.put(
        source,
        "defaults",
        Map.put(defaults, "capabilities", Map.put(capabilities, kind, selection))
      )
    end
  end

  defp default_capabilities(source) do
    source
    |> Map.get("defaults", %{})
    |> object!("defaults")
    |> Map.get("capabilities", %{})
    |> object!("default capabilities")
  end

  defp media_policy(source, %{"while_present" => entry_policy}) do
    entry_policy = object!(entry_policy, "entry while_present")
    call_policy = source |> Map.get("media_policy", %{}) |> object!("call media_policy")

    check!(
      Map.keys(entry_policy) -- (@flags ++ @route_fields) == [],
      "unknown entry media policy field"
    )

    if map_size(entry_policy) == 0 do
      source
    else
      Enum.each(entry_policy, fn {field, value} -> validate_media!(field, value) end)

      policy =
        Map.merge(call_policy, entry_policy, fn field, left, right ->
          validate_media!(field, left)
          intersect(field, left, right)
        end)

      Map.put(source, "media_policy", policy)
    end
  end

  defp media_policy(source, _entry), do: source

  defp validate_media!(field, value) when field in @flags,
    do: check!(is_boolean(value), "invalid media recording permission")

  defp validate_media!(_field, value) do
    routes = object!(value, "media routes")

    check!(
      Enum.all?(routes, fn {from, refs} ->
        is_binary(from) and is_list(refs) and Enum.all?(refs, &is_binary/1)
      end),
      "invalid media routes"
    )
  end

  defp intersect(field, left, right) when field in @flags, do: left and right

  defp intersect(_field, left, right) do
    for {from, refs} <- left,
        Map.has_key?(right, from),
        into: %{},
        do: {from, Enum.filter(refs, &(&1 in Map.fetch!(right, from)))}
  end

  defp object!(value, field) do
    check!(is_map(value), "#{field} must be an object")
    value
  end

  defp check!(true, _reason), do: :ok
  defp check!(false, reason), do: throw({:incompatible, reason})
end
