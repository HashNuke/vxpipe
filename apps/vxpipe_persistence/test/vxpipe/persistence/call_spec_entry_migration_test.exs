defmodule Vxpipe.Persistence.CallSpecEntryMigrationTest do
  use Vxpipe.Persistence.DataCase, async: false

  @migration Path.expand(
               "../../../priv/repo/migrations/20261126013600_migrate_call_spec_entry_settings.exs",
               __DIR__
             )
  Code.require_file(@migration)
  alias Vxpipe.Persistence.Repo.Migrations.MigrateCallSpecEntrySettings

  @current "20261125.01"
  @directional "20261004.01"
  @legacy "20260915.01"
  @voice %{"provider" => "morse", "model" => "morse"}
  @other_voice %{
    "provider" => "deepgram",
    "model" => "flux-haley-en",
    "options" => %{"sample_rate" => 24_000, "encoding" => "linear16"}
  }

  setup do
    Repo.query!("""
    CREATE TEMP TABLE call_spec_revisions (
      id bigint PRIMARY KEY, call_spec_id bigint, revision integer, schema_version text,
      source jsonb, source_digest text, compiled_metadata jsonb, validation_errors jsonb[]
    ) ON COMMIT DROP
    """)

    :ok
  end

  test "rewrites caller, callee and directionless historical revisions in place and keeps current rows unchanged" do
    october = source(@directional)
    september = source(@legacy)

    outgoing =
      october
      |> Map.delete("incoming_call")
      |> Map.put("outgoing_call", %{
        "callee" => "entry",
        "handled_by" => "agent",
        "ring_timeout_ms" => 9_000
      })
      |> put_in(["participants", "entry", "connection"], %{
        "service" => "phone",
        "mode" => "dial",
        "number" => "+15550001000"
      })
      |> put_in(["defaults", "capabilities", "speech_to_text"], @voice)
      |> put_in(["defaults", "capabilities", "text_to_speech"], @voice)
      |> put_in(["opening_audio", "text_to_speech"], @other_voice)
      |> put_in(["participants", "entry", "capabilities", "speech_to_text"], %{
        "provider" => "fixture",
        "model" => "different"
      })

    put_revision(1, september)
    put_revision(2, october)
    put_revision(3, outgoing)
    put_revision(4, %{"schema_version" => @current, "name" => "leave untouched"})
    current = row(4)

    Repo.query!(
      "CREATE TEMP TABLE entry_route_refs (row_id bigint REFERENCES call_spec_revisions(id), ref text) ON COMMIT DROP"
    )

    Repo.query!(
      "INSERT INTO entry_route_refs VALUES (1,'historical-route'),(4,'live-publication')"
    )

    migrate()

    for id <- [1, 2, 3] do
      [@current, migrated, digest, metadata, []] = row(id)
      assert migrated["schema_version"] == @current
      refute Map.has_key?(migrated["participants"]["entry"], "capabilities")
      refute Map.has_key?(migrated["participants"]["entry"], "while_present")
      refute Map.has_key?(migrated, "entry_caller")
      refute Map.has_key?(migrated, "entry_receiver")
      assert migrated["defaults"]["capabilities"]["text_to_speech"] == @voice
      assert migrated["defaults"]["capabilities"]["speech_to_text"] == @voice
      assert migrated["opening_audio"] == %{"type" => "text", "text" => "Welcome"}
      assert migrated["participants"]["agent"] == october["participants"]["agent"]
      assert digest == digest(migrated)
      assert metadata["schema_version"] == @current
      assert metadata["agent_protocol"] == %{"pinned" => true}
      assert {:ok, _} = Vxpipe.CallEngine.CallSpec.new(migrated, resource_id: "77", revision: id)
    end

    [_, converted, _, _, _] = row(1)
    assert converted["incoming_call"] == october["incoming_call"]
    [_, converted, _, _, _] = row(3)
    assert converted["outgoing_call"] == outgoing["outgoing_call"]
    assert row(4) == current
    snapshot = Enum.map(1..4, &row/1)
    migrate()
    assert Enum.map(1..4, &row/1) == snapshot

    assert Repo.query!("SELECT row_id, ref FROM entry_route_refs ORDER BY row_id").rows == [
             [1, "historical-route"],
             [4, "live-publication"]
           ]
  end

  test "keeps the stricter entry recording and routing policy and preserves historical draft errors" do
    errors = [
      %{
        "code" => "unsupported_agent_protocol",
        "details" => %{"path" => ["participants", "agent", "tools"]}
      }
    ]

    draft =
      source(@directional)
      |> put_in(["participants", "agent", "prompt"], nil)
      |> put_in(["participants", "entry", "while_present"], %{
        "record_audio" => false,
        "save_transcripts" => true,
        "audio_routes" => %{"entry" => ["agent"], "agent" => ["entry"]},
        "transcript_routes" => %{}
      })
      |> Map.put("media_policy", %{
        "record_audio" => true,
        "save_transcripts" => false,
        "audio_routes" => %{"entry" => ["agent", "entry"]}
      })

    put_revision(1, draft, errors)
    migrate()
    [@current, migrated, _, _, ^errors] = row(1)

    assert migrated["media_policy"] == %{
             "record_audio" => false,
             "save_transcripts" => false,
             "audio_routes" => %{"entry" => ["agent"]},
             "transcript_routes" => %{}
           }

    assert migrated["participants"]["agent"]["prompt"] == nil
  end

  test "reports an incompatible legacy entry by row without disclosing source contents" do
    broken =
      source(@legacy) |> put_in(["participants", "entry", "connection", "admission"], "transfer")

    put_revision(7, broken)
    error = assert_raise RuntimeError, fn -> migrate() end
    assert error.message =~ "call_spec_id=77 revision=7"
    assert error.message =~ "connection"
    refute error.message =~ "Welcome"
    assert List.first(row(7)) == @legacy
  end

  test "an incompatible text opening rolls back earlier revisions in the migration transaction" do
    put_revision(1, source(@directional))

    incompatible =
      source(@directional)
      |> put_in(["defaults", "capabilities"], %{})
      |> put_in(["participants", "agent", "capabilities"], %{"speech_to_speech" => @voice})

    put_revision(2, incompatible)

    originals = Enum.map(1..2, &row/1)

    error =
      assert_raise RuntimeError, fn ->
        Repo.transaction(fn -> migrate() end, mode: :savepoint)
      end

    assert error.message =~ "call_spec_id=77 revision=2"
    assert error.message =~ "speech-to-speech"
    assert Enum.map(1..2, &row/1) == originals
  end

  defp source(version) do
    source = %{
      "schema_version" => version,
      "opening_audio" => %{"type" => "text", "text" => "Welcome", "text_to_speech" => @voice},
      "defaults" => %{
        "capabilities" => %{"model_inference" => %{"provider" => "fixture", "model" => "test"}}
      },
      "participants" => %{
        "entry" => %{
          "type" => "human",
          "connection" => %{"service" => "web", "mode" => "receive", "admission" => "start_call"},
          "capabilities" => %{"speech_to_text" => @voice}
        },
        "agent" => %{"type" => "agent", "prompt" => "Answer questions."}
      }
    }

    if version == @legacy,
      do: Map.merge(source, %{"entry_caller" => "entry", "entry_receiver" => "agent"}),
      else: Map.put(source, "incoming_call", %{"caller" => "entry", "handled_by" => "agent"})
  end

  defp put_revision(id, source, errors \\ []) do
    Repo.query!(
      "INSERT INTO call_spec_revisions VALUES ($1, 77, $2, $3, $4, $5, $6, $7)",
      [
        id,
        id,
        source["schema_version"],
        source,
        digest(source),
        %{"schema_version" => source["schema_version"], "agent_protocol" => %{"pinned" => true}},
        errors
      ]
    )
  end

  defp row(id),
    do:
      Repo.query!(
        "SELECT schema_version, source, source_digest, compiled_metadata, validation_errors FROM call_spec_revisions WHERE id=$1",
        [id]
      ).rows
      |> List.first()

  defp digest(source),
    do: :crypto.hash(:sha256, JSON.encode!(source)) |> Base.encode16(case: :lower)

  defp migrate,
    do:
      Ecto.Migration.Runner.run(
        Repo,
        Repo.config(),
        20_261_126_013_600,
        MigrateCallSpecEntrySettings,
        :forward,
        :up,
        :up,
        prefix: "pg_temp",
        log: false
      )
end
