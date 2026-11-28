defmodule Vxpipe.Providers.Google.DecisionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Google.Decisions

  @evidence "caller: hello"
  @model "gemini-decision-1"
  @resource_model "models/gemini-decision-1"
  @endpoint "https://generativelanguage.googleapis.com/v1beta/decisions"

  @questions [
    %{id: "private_request", question: "Is the caller asking about their own account?"},
    %{
      id: "private_disclosure",
      question: "Does this response disclose another patient's details?"
    }
  ]

  @request_fixture %{
    "model" => @resource_model,
    "input" => @evidence,
    "questions" => %{
      "private_request" => %{
        "type" => "noul",
        "instructions" => "Is the caller asking about their own account?"
      },
      "private_disclosure" => %{
        "type" => "noul",
        "instructions" => "Does this response disclose another patient's details?"
      }
    }
  }

  @answers_fixture %{
    "private_request" => %{"type" => "noul", "noul" => 0.3, "confidence" => 0.7},
    "private_disclosure" => %{"type" => "noul", "noul" => 0.9, "confidence" => 0.9}
  }

  @usage_fixture %{"total_input_tokens" => 42, "total_output_tokens" => 4, "total_tokens" => 46}

  defp success_response(answers \\ @answers_fixture, usage \\ @usage_fixture) do
    %{"answers" => answers, "usage" => usage}
  end

  test "builds the official Decisions wire body without policy leakage" do
    assert {:ok, config} = Decisions.new(api_key: "synthetic-google-key", model: @model)
    refute inspect(config) =~ "synthetic-google-key"

    assert {:ok, body} = Decisions.request_body(config, @evidence, @questions)

    # Exact wire payload: Req serializes `body` to JSON, so the decoded JSON
    # must equal the fixture (keyed noul questions, resource model, input).
    assert JSON.decode!(JSON.encode!(body)) == @request_fixture

    encoded = JSON.encode!(body)
    refute encoded =~ "generateContent"
    refute encoded =~ "candidates"
    refute encoded =~ "required_answer"
    refute encoded =~ "threshold"
    refute encoded =~ "synthetic-google-key"
  end

  test "successful batch maps keyed noul answers and usage while the actual model stays unknown" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1beta/decisions"
      assert Plug.Conn.get_req_header(conn, "x-goog-api-key") == ["synthetic-google-key"]

      body = JSON.decode!(Req.Test.raw_body(conn))
      assert body == @request_fixture

      Req.Test.json(conn, success_response())
    end)

    assert {:ok, config} = Decisions.new(api_key: "synthetic-google-key", model: @model)

    assert {:ok, result} =
             Decisions.evaluate(config, @evidence, @questions, plug: {Req.Test, __MODULE__})

    assert result.model == nil
    assert result.probabilities == %{"private_request" => 0.3, "private_disclosure" => 0.9}
    assert result.usage == %{input_tokens: 42, output_tokens: 4, total_tokens: 46}
    assert result.attempts == 1
    assert is_integer(result.elapsed_ms)
  end

  test "prompt feedback block is a typed refused error" do
    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "prompt_feedback" => %{"block_reason" => "safety", "block_reason_message" => "blocked"},
        "usage" => @usage_fixture
      })
    end)

    assert {:ok, config} = Decisions.new(api_key: "synthetic-google-key", model: @model)

    assert {:error, :refused} =
             Decisions.evaluate(config, @evidence, @questions, plug: {Req.Test, __MODULE__})
  end

  test "duplicate, unknown, coerced, mistyped or out-of-range answers are invalid" do
    payloads = [
      %{
        "private_request" => %{"type" => "noul", "noul" => 0.3, "confidence" => 0.7},
        "private_request_dup" => %{"type" => "noul", "noul" => 0.3, "confidence" => 0.7}
      },
      %{
        "private_request" => %{"type" => "noul", "noul" => 0.3, "confidence" => 0.7}
      },
      %{
        "private_request" => %{"type" => "noul", "noul" => "0.3", "confidence" => 0.7},
        "private_disclosure" => %{"type" => "noul", "noul" => 0.9, "confidence" => 0.9}
      },
      %{
        "private_request" => %{"type" => "noul", "noul" => 1.5, "confidence" => 0.9},
        "private_disclosure" => %{"type" => "noul", "noul" => 0.9, "confidence" => 0.9}
      },
      %{
        "private_request" => %{"type" => "choice", "noul" => 0.3, "confidence" => 0.7},
        "private_disclosure" => %{"type" => "noul", "noul" => 0.9, "confidence" => 0.9}
      }
    ]

    for answers <- payloads do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, success_response(answers))
      end)

      assert {:ok, config} = Decisions.new(api_key: "synthetic-google-key", model: @model)

      assert {:error, :invalid_result} =
               Decisions.evaluate(config, @evidence, @questions, plug: {Req.Test, __MODULE__})
    end
  end

  test "one bounded retry on 429/503 then success; no retry on auth" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(429)
      |> Req.Test.json(%{"error" => %{"message" => "rate limited"}})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, success_response())
    end)

    assert {:ok, config} = Decisions.new(api_key: "synthetic-google-key", model: @model)

    assert {:ok, result} =
             Decisions.evaluate(config, @evidence, @questions,
               plug: {Req.Test, __MODULE__},
               sleep: fn _ms -> :ok end
             )

    assert result.attempts == 2

    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => %{"message" => "bad key"}})
    end)

    assert {:error, :unauthorized} =
             Decisions.evaluate(config, @evidence, @questions, plug: {Req.Test, __MODULE__})
  end

  test "double retryable failure exhausts the single retry" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(503)
      |> Req.Test.json(%{"error" => %{"message" => "overloaded"}})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(503)
      |> Req.Test.json(%{"error" => %{"message" => "overloaded"}})
    end)

    assert {:ok, config} = Decisions.new(api_key: "synthetic-google-key", model: @model)

    assert {:error, :retry_exhausted} =
             Decisions.evaluate(config, @evidence, @questions,
               plug: {Req.Test, __MODULE__},
               sleep: fn _ms -> :ok end
             )
  end

  test "oversize and invalid configuration never reach HTTP" do
    assert {:ok, config} = Decisions.new(api_key: "synthetic-google-key", model: @model)

    assert {:error, :oversized} =
             Decisions.evaluate(config, String.duplicate("x", 49_153), @questions,
               plug: {Req.Test, __MODULE__}
             )

    assert {:error, :invalid_configuration} = Decisions.new(api_key: "", model: @model)

    assert {:error, :invalid_configuration} =
             Decisions.new(api_key: "synthetic-google-key", model: "unknown")
  end

  test "expired deadline times out before any HTTP attempt" do
    assert {:ok, config} = Decisions.new(api_key: "synthetic-google-key", model: @model)
    past = System.monotonic_time(:millisecond) - 1

    assert {:error, :timeout} =
             Decisions.evaluate(config, @evidence, @questions,
               plug: {Req.Test, __MODULE__},
               deadline_ms: past
             )
  end

  test "missing usage stays unknown and never invents token counts" do
    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"answers" => @answers_fixture})
    end)

    assert {:ok, config} = Decisions.new(api_key: "synthetic-google-key", model: @model)

    assert {:ok, result} =
             Decisions.evaluate(config, @evidence, @questions, plug: {Req.Test, __MODULE__})

    assert result.usage == :unknown
  end

  test "pins the official Gemini Decisions contract" do
    assert Decisions.models() == [@model]
    assert Decisions.endpoint() == @endpoint
    refute Decisions.endpoint() =~ "generateContent"
  end

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end
end
