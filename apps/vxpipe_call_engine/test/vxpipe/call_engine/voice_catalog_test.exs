defmodule Vxpipe.CallEngine.VoiceCatalogTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.VoiceCatalog

  @scope %{provider: "elevenlabs", capability: "text_to_speech", model: "eleven_flash_v2_5"}
  @payload %{"api_key" => "private-test-key"}
  @query %{"search" => "George", "filters" => %{"gender" => "male"}, "cursor" => "next-page"}

  test "describes installed models without making a provider request" do
    assert {:ok, descriptor} = VoiceCatalog.describe(@scope)
    assert descriptor.providerName == "ElevenLabs"
    assert descriptor.modelName == "Eleven Flash v2.5"
    assert descriptor.search
    assert Enum.any?(descriptor.filters, &(&1.key == "gender"))
    assert {:error, :invalid_voice_scope} = VoiceCatalog.describe(%{@scope | model: "invented"})

    assert {:error, :invalid_voice_scope} =
             VoiceCatalog.describe(%{@scope | capability: "model_inference"})
  end

  test "normalizes authenticated search, filters and pagination without exposing upstream metadata" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.host == "api.elevenlabs.io"
      assert conn.request_path == "/v2/voices"
      assert Plug.Conn.get_req_header(conn, "xi-api-key") == ["private-test-key"]
      assert conn.query_params["search"] == "George"
      assert conn.query_params["gender"] == "male"
      assert conn.query_params["next_page_token"] == "next-page"
      assert conn.query_params["page_size"] == "50"
      assert conn.query_params["include_total_count"] == "false"

      Req.Test.json(conn, %{
        "voices" => [voice()],
        "has_more" => true,
        "next_page_token" => "page-3"
      })
    end)

    assert {:ok, %{voices: [result], nextCursor: "page-3"}} = list(@query)
    assert result.id == "voice-1"
    assert result.name == "George"
    assert result.attributes == [%{key: "gender", label: "Gender", value: "male"}]
    refute JSON.encode!(result) =~ "private-sentinel"
  end

  test "looks up a saved ID directly, even when it was not on the first page" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/v1/voices/voice-1"
      Req.Test.json(conn, voice())
    end)

    assert {:ok, %{id: "voice-1"}} =
             VoiceCatalog.get(@scope, "voice-1", @payload, plug: {Req.Test, __MODULE__})

    Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 404, "private-sentinel"))

    assert {:ok, nil} =
             VoiceCatalog.get(@scope, "voice-1", @payload, plug: {Req.Test, __MODULE__})
  end

  test "rejects unsupported filters, oversized queries and unsafe IDs before HTTP" do
    Req.Test.stub(__MODULE__, fn _ -> flunk("invalid input reached the provider") end)

    for query <- [
          %{"filters" => %{"endpoint" => "https://example.test"}},
          %{"search" => String.duplicate("x", 257)},
          %{"cursor" => String.duplicate("x", 2049)},
          %{"filters" => %{"gender" => ["male"]}}
        ] do
      assert {:error, :invalid_voice_query} = list(query)
    end

    assert {:error, :invalid_voice_query} =
             VoiceCatalog.get(@scope, "../private", @payload, plug: {Req.Test, __MODULE__})
  end

  test "returns sanitized errors and rejects malformed or excessive upstream bodies" do
    for {status, reason} <- [
          {401, :voice_catalog_credentials_rejected},
          {403, :voice_catalog_credentials_rejected},
          {429, :voice_catalog_rate_limited},
          {503, :voice_catalog_unavailable},
          {302, :voice_catalog_unavailable}
        ] do
      Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, status, "private-sentinel"))
      assert {:error, ^reason} = list(%{})
    end

    for body <- [
          %{"voices" => "bad"},
          %{"voices" => [%{"voice_id" => "no-name"}], "has_more" => false},
          %{"voices" => [], "has_more" => true}
        ] do
      Req.Test.stub(__MODULE__, &Req.Test.json(&1, body))
      assert {:error, :invalid_voice_catalog_response} = list(%{})
    end

    Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 200, String.duplicate("x", 2_097_153)))
    assert {:error, :invalid_voice_catalog_response} = list(%{})
  end

  test "excludes voices explicitly incompatible with the selected model without losing the cursor" do
    Req.Test.stub(
      __MODULE__,
      &Req.Test.json(&1, %{
        "voices" => [
          Map.merge(voice(), %{
            "category" => "professional",
            "fine_tuning" => %{"state" => %{"eleven_flash_v2_5" => "failed"}}
          })
        ],
        "has_more" => true,
        "next_page_token" => "next"
      })
    )

    assert {:ok, %{voices: [], nextCursor: "next"}} = list(%{})
  end

  test "quality recommendations are not treated as model compatibility restrictions" do
    Req.Test.stub(
      __MODULE__,
      &Req.Test.json(&1, %{
        "voices" => [Map.put(voice(), "high_quality_base_model_ids", ["eleven_v3"])],
        "has_more" => false
      })
    )

    assert {:ok, %{voices: [%{id: "voice-1"}]}} = list(%{})
  end

  test "finite model voices reuse the same catalog shape without HTTP" do
    scope = %{provider: "morse_code_api", capability: "text_to_speech", model: "morse_v1"}

    assert {:ok, %{voices: [%{id: "morse", name: "Morse 700 Hz"}], nextCursor: nil}} =
             VoiceCatalog.list(scope, %{}, %{})

    assert {:ok, %{voices: []}} = VoiceCatalog.list(scope, %{"search" => "no-match"}, %{})
    assert {:ok, nil} = VoiceCatalog.get(scope, "missing", %{})
  end

  defp list(query), do: VoiceCatalog.list(@scope, query, @payload, plug: {Req.Test, __MODULE__})

  defp voice,
    do: %{
      "voice_id" => "voice-1",
      "name" => "George",
      "description" => "Warm voice",
      "labels" => %{"gender" => "male", "internal" => "private-sentinel"},
      "sharing" => %{"email" => "private-sentinel"}
    }
end
