defmodule Vxpipe.Providers.OpenAI.DecisionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.OpenAI.Decisions

  @questions [
    %{id: "private_request", question: "Is the caller asking about their own account?"},
    %{
      id: "private_disclosure",
      question: "Does this response disclose another patient's details?"
    }
  ]

  test "builds the official Decisions wire body without policy leakage" do
    assert {:ok, config} = Decisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")
    refute inspect(config) =~ "synthetic-openai-key"

    assert {:ok, body} = Decisions.request_body(config, "caller: hello", @questions)

    assert body[:model] == "gpt-6-luna"
    assert body[:input] == "caller: hello"

    assert body[:questions] == [
             %{
               name: "private_request",
               type: "predicate",
               instructions: "Is the caller asking about their own account?"
             },
             %{
               name: "private_disclosure",
               type: "predicate",
               instructions: "Does this response disclose another patient's details?"
             }
           ]

    encoded = JSON.encode!(body)
    refute encoded =~ "required_answer"
    refute encoded =~ "probability_threshold"
    refute encoded =~ "synthetic-openai-key"
  end

  test "successful batch maps exact named P(Yes) with actual model and safe usage" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/decisions"
      [auth] = Plug.Conn.get_req_header(conn, "authorization")
      assert auth == "Bearer synthetic-openai-key"

      body = JSON.decode!(Req.Test.raw_body(conn))
      assert body["model"] == "gpt-6-luna"

      assert [%{"name" => "private_request"}, %{"name" => "private_disclosure"}] =
               body["questions"]

      Req.Test.json(conn, %{
        "model" => "gpt-6-luna",
        "answers" => [
          %{"type" => "predicate", "name" => "private_request", "probability" => 0.3},
          %{"type" => "predicate", "name" => "private_disclosure", "probability" => 0.9}
        ],
        "usage" => %{"input_tokens" => 42, "output_tokens" => 0, "total_tokens" => 42}
      })
    end)

    assert {:ok, config} = Decisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    assert {:ok, result} =
             Decisions.evaluate(config, "caller: hello", @questions, plug: {Req.Test, __MODULE__})

    assert result.model == "gpt-6-luna"
    assert result.probabilities == %{"private_request" => 0.3, "private_disclosure" => 0.9}
    assert result.usage == %{input_tokens: 42, output_tokens: 0, total_tokens: 42}
    assert result.attempts == 1
    assert is_integer(result.elapsed_ms)
  end

  test "per-question refusal is a typed error without invented scores" do
    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "model" => "gpt-6-luna",
        "answers" => [
          %{"type" => "predicate", "name" => "private_request", "probability" => 0.1},
          %{"type" => "refusal", "name" => "private_disclosure"}
        ],
        "usage" => %{"input_tokens" => 10, "output_tokens" => 0, "total_tokens" => 10}
      })
    end)

    assert {:ok, config} = Decisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    assert {:error, :refused} =
             Decisions.evaluate(config, "caller: hello", @questions, plug: {Req.Test, __MODULE__})
  end

  test "duplicate, unknown, coerced or out-of-range answers are invalid" do
    cases = [
      %{
        "model" => "gpt-6-luna",
        "answers" => [
          %{"type" => "predicate", "name" => "private_request", "probability" => 0.3},
          %{"type" => "predicate", "name" => "private_request", "probability" => 0.3}
        ]
      },
      %{
        "model" => "gpt-6-luna",
        "answers" => [
          %{"type" => "predicate", "name" => "private_request", "probability" => 0.3},
          %{"type" => "predicate", "name" => "unknown_q", "probability" => 0.3}
        ]
      },
      %{
        "model" => "gpt-6-luna",
        "answers" => [
          %{"type" => "predicate", "name" => "private_request", "probability" => "0.3"},
          %{"type" => "predicate", "name" => "private_disclosure", "probability" => 0.9}
        ]
      },
      %{
        "model" => "gpt-6-luna",
        "answers" => [
          %{"type" => "predicate", "name" => "private_request", "probability" => 1.5},
          %{"type" => "predicate", "name" => "private_disclosure", "probability" => 0.9}
        ]
      },
      %{
        "model" => "gpt-6-luna",
        "answers" => [
          %{"type" => "predicate", "name" => "private_request", "probability" => 0.3}
        ]
      }
    ]

    for payload <- cases do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, payload) end)

      assert {:ok, config} = Decisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

      assert {:error, :invalid_result} =
               Decisions.evaluate(config, "caller: hello", @questions,
                 plug: {Req.Test, __MODULE__}
               )
    end
  end

  test "one bounded retry on 429 then success; no retry on auth or validation" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{"error" => "rate limited"})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "model" => "gpt-6-luna",
        "answers" => [
          %{"type" => "predicate", "name" => "private_request", "probability" => 0.3},
          %{"type" => "predicate", "name" => "private_disclosure", "probability" => 0.9}
        ],
        "usage" => %{"input_tokens" => 1, "output_tokens" => 0, "total_tokens" => 1}
      })
    end)

    assert {:ok, config} = Decisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    assert {:ok, result} =
             Decisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               sleep: fn _ms -> :ok end
             )

    assert result.attempts == 2

    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => "bad key"})
    end)

    assert {:error, :unauthorized} =
             Decisions.evaluate(config, "caller: hello", @questions, plug: {Req.Test, __MODULE__})

    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"error" => "bad request"})
    end)

    assert {:error, :invalid_result} =
             Decisions.evaluate(config, "caller: hello", @questions, plug: {Req.Test, __MODULE__})
  end

  test "second consecutive retryable status exhausts the single retry" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{"error" => "overloaded"})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{"error" => "overloaded"})
    end)

    assert {:ok, config} = Decisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    assert {:error, :retry_exhausted} =
             Decisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               sleep: fn _ms -> :ok end
             )
  end

  test "oversize evidence and question bounds are explicit errors without HTTP" do
    assert {:ok, config} = Decisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    assert {:error, :oversized} =
             Decisions.evaluate(config, String.duplicate("x", 49_153), @questions,
               plug: {Req.Test, __MODULE__}
             )

    too_many = for i <- 1..33, do: %{id: "q_#{i}", question: "Is this ok?"}

    assert {:error, :oversized} =
             Decisions.evaluate(config, "caller: hello", too_many, plug: {Req.Test, __MODULE__})

    assert {:error, :invalid_configuration} = Decisions.new(api_key: "", model: "gpt-6-luna")

    assert {:error, :invalid_configuration} =
             Decisions.new(api_key: "synthetic-openai-key", model: "unknown")
  end

  test "expired deadline times out before any HTTP attempt" do
    assert {:ok, config} = Decisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")
    past = System.monotonic_time(:millisecond) - 1

    assert {:error, :timeout} =
             Decisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               deadline_ms: past
             )
  end

  test "missing usage stays unknown and never invents token counts" do
    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "model" => "gpt-6-luna",
        "answers" => [
          %{"type" => "predicate", "name" => "private_request", "probability" => 0.3},
          %{"type" => "predicate", "name" => "private_disclosure", "probability" => 0.9}
        ]
      })
    end)

    assert {:ok, config} = Decisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    assert {:ok, result} =
             Decisions.evaluate(config, "caller: hello", @questions, plug: {Req.Test, __MODULE__})

    assert result.usage == :unknown
  end

  test "pins the official OpenAI Decisions contract" do
    assert Decisions.models() == ["gpt-6-luna"]
    assert Decisions.endpoint() == "https://api.openai.com/v1/decisions"
  end

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end
end
