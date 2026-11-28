defmodule Vxpipe.Providers.DecisionsAttemptsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Google.Decisions, as: GoogleDecisions
  alias Vxpipe.Providers.Jev.Decisions, as: JevDecisions
  alias Vxpipe.Providers.OpenAI.Decisions, as: OpenAIDecisions

  @questions [
    %{id: "private_request", question: "Is the caller asking about their own account?"},
    %{
      id: "private_disclosure",
      question: "Does this response disclose another patient's details?"
    }
  ]

  test "openai success emits started/finished with ordinal, model, usage and elapsed" do
    parent = self()
    on_attempt = fn event -> send(parent, {:attempt, event}) end

    Req.Test.expect(__MODULE__, fn conn ->
      conn = Plug.Conn.put_resp_header(conn, "x-request-id", "dec_123")

      Req.Test.json(conn, %{
        "model" => "gpt-6-luna",
        "answers" => [
          %{"type" => "predicate", "name" => "private_request", "probability" => 0.3},
          %{"type" => "predicate", "name" => "private_disclosure", "probability" => 0.9}
        ],
        "usage" => %{"input_tokens" => 42, "output_tokens" => 0, "total_tokens" => 42}
      })
    end)

    assert {:ok, config} =
             OpenAIDecisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    assert {:ok, result} =
             OpenAIDecisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               on_attempt: on_attempt
             )

    assert result.request_id == "dec_123"
    assert_received {:attempt, %{phase: :started, ordinal: 1, started_at_ms: started}}
    assert is_integer(started)

    assert_received {:attempt,
                     %{
                       phase: :finished,
                       ordinal: 1,
                       outcome: :succeeded,
                       error_code: nil,
                       request_id: "dec_123",
                       model: "gpt-6-luna",
                       usage: %{input_tokens: 42, output_tokens: 0, total_tokens: 42}
                     } = finished}

    assert is_integer(finished.ended_at_ms)
    assert is_integer(finished.duration_ms)
    assert is_integer(finished.elapsed_ms)
    assert finished.probabilities == %{"private_request" => 0.3, "private_disclosure" => 0.9}
  end

  test "openai retry emits failed first attempt then succeeded second attempt" do
    parent = self()
    on_attempt = fn event -> send(parent, {:attempt, event}) end

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

    assert {:ok, config} =
             OpenAIDecisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    assert {:ok, result} =
             OpenAIDecisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               sleep: fn _ms -> :ok end,
               on_attempt: on_attempt
             )

    assert result.attempts == 2
    assert result.request_id == nil

    assert_received {:attempt, %{phase: :started, ordinal: 1}}
    assert_received {:attempt, %{phase: :finished, ordinal: 1, outcome: :failed} = first}
    assert first.error_code in [:rate_limited, :retryable, :unavailable, :retry_exhausted]
    assert_received {:attempt, %{phase: :started, ordinal: 2}}
    assert_received {:attempt, %{phase: :finished, ordinal: 2, outcome: :succeeded}}
  end

  test "openai refusal emits failed termination with partial trustworthy answers" do
    parent = self()
    on_attempt = fn event -> send(parent, {:attempt, event}) end

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

    assert {:ok, config} =
             OpenAIDecisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    assert {:error, :refused} =
             OpenAIDecisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               on_attempt: on_attempt
             )

    assert_received {:attempt, %{phase: :started, ordinal: 1}}

    assert_received {:attempt,
                     %{phase: :finished, ordinal: 1, outcome: :failed, error_code: :refused} =
                       finished}

    assert finished.probabilities == %{"private_request" => 0.1}
    assert finished.usage == %{input_tokens: 10, output_tokens: 0, total_tokens: 10}
  end

  test "jev success emits started/finished with safe telemetry" do
    parent = self()
    on_attempt = fn event -> send(parent, {:attempt, event}) end

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "id" => "jev_1",
        "model" => "jev-1.14.0",
        "answers" => %{
          "private_request" => %{"type" => "noul", "noul" => 0.3},
          "private_disclosure" => %{"type" => "noul", "noul" => 0.9}
        },
        "usage" => %{"input_tokens" => 120, "output_tokens" => 12}
      })
    end)

    assert {:ok, config} = JevDecisions.new(api_key: "synthetic-jev-key", model: "jev-1.14.0")

    assert {:ok, result} =
             JevDecisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               on_attempt: on_attempt
             )

    assert result.request_id == "jev_1"
    assert_received {:attempt, %{phase: :started, ordinal: 1}}
    assert_received {:attempt, %{phase: :finished, ordinal: 1, outcome: :succeeded} = finished}
    assert finished.model == "jev-1.14.0"
    assert finished.usage == %{input_tokens: 120, output_tokens: 12}
  end

  test "expired deadline emits no attempt events" do
    parent = self()
    on_attempt = fn event -> send(parent, {:attempt, event}) end

    assert {:ok, config} =
             OpenAIDecisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    past = System.monotonic_time(:millisecond) - 1

    assert {:error, :timeout} =
             OpenAIDecisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               deadline_ms: past,
               on_attempt: on_attempt
             )

    refute_received {:attempt, _}
  end

  test "invalid observer never breaks evaluation" do
    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "model" => "jev-1.14.0",
        "answers" => %{
          "private_request" => %{"type" => "noul", "noul" => 0.3},
          "private_disclosure" => %{"type" => "noul", "noul" => 0.9}
        },
        "usage" => %{"input_tokens" => 5, "output_tokens" => 1}
      })
    end)

    assert {:ok, config} = JevDecisions.new(api_key: "synthetic-jev-key", model: "jev-1.14.0")

    assert {:ok, _result} =
             JevDecisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               on_attempt: :not_a_function
             )
  end

  test "openai malformed batch retains trustworthy subset while overall is error" do
    parent = self()
    on_attempt = fn event -> send(parent, {:attempt, event}) end

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "model" => "gpt-6-luna",
        "answers" => [
          %{"type" => "predicate", "name" => "private_request", "probability" => 0.3},
          %{"type" => "predicate", "name" => "private_disclosure", "probability" => "bad"}
        ],
        "usage" => %{"input_tokens" => 7, "output_tokens" => 1, "total_tokens" => 8}
      })
    end)

    assert {:ok, config} =
             OpenAIDecisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    assert {:error, :invalid_result} =
             OpenAIDecisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               on_attempt: on_attempt
             )

    assert_received {:attempt, %{phase: :started, ordinal: 1}}

    assert_received {:attempt,
                     %{
                       phase: :finished,
                       ordinal: 1,
                       outcome: :failed,
                       error_code: :invalid_result
                     } = finished}

    assert finished.probabilities == %{"private_request" => 0.3}
    assert finished.usage == %{input_tokens: 7, output_tokens: 1, total_tokens: 8}
    # Error return carries no semantic feedback (2-tuple error, no scores).
  end

  test "timeout after submission emits failed attempt with safe classification" do
    parent = self()
    on_attempt = fn event -> send(parent, {:attempt, event}) end
    http_fun = fn _endpoint, _opts -> {:error, %Req.TransportError{reason: :timeout}} end

    assert {:ok, config} =
             OpenAIDecisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    assert {:error, :timeout} =
             OpenAIDecisions.evaluate(config, "caller: hello", @questions,
               http_fun: http_fun,
               on_attempt: on_attempt
             )

    assert_received {:attempt, %{phase: :started, ordinal: 1}}

    assert_received {:attempt,
                     %{phase: :finished, ordinal: 1, outcome: :failed, error_code: :timeout} =
                       finished}

    assert finished.request_id == nil
    assert finished.usage == :unknown
    assert is_integer(finished.duration_ms)
    assert is_integer(finished.elapsed_ms)
  end

  test "google success records usage while an unreported model stays unknown" do
    parent = self()
    on_attempt = fn event -> send(parent, {:attempt, event}) end

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "answers" => %{
          "private_request" => %{"type" => "noul", "noul" => 0.3},
          "private_disclosure" => %{"type" => "noul", "noul" => 0.9}
        },
        "usage" => %{"total_input_tokens" => 42, "total_output_tokens" => 4, "total_tokens" => 46}
      })
    end)

    assert {:ok, config} =
             GoogleDecisions.new(api_key: "synthetic-google-key", model: "gemini-decision-1")

    assert {:ok, result} =
             GoogleDecisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               on_attempt: on_attempt
             )

    assert result.model == nil
    assert result.request_id == nil
    assert result.usage == %{input_tokens: 42, output_tokens: 4, total_tokens: 46}
    assert_received {:attempt, %{phase: :finished, ordinal: 1, outcome: :succeeded} = finished}
    assert finished.model == nil
    assert finished.probabilities == %{"private_request" => 0.3, "private_disclosure" => 0.9}
  end

  test "google malformed batch retains trustworthy subset" do
    parent = self()
    on_attempt = fn event -> send(parent, {:attempt, event}) end

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "answers" => %{
          "private_request" => %{"type" => "noul", "noul" => 0.3},
          "private_disclosure" => %{"type" => "noul", "noul" => "bad"}
        }
      })
    end)

    assert {:ok, config} =
             GoogleDecisions.new(api_key: "synthetic-google-key", model: "gemini-decision-1")

    assert {:error, :invalid_result} =
             GoogleDecisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               on_attempt: on_attempt
             )

    assert_received {:attempt, %{phase: :finished, ordinal: 1, outcome: :failed} = finished}
    assert finished.probabilities == %{"private_request" => 0.3}
  end

  test "jev retryable then success emits two attempts with safe error code" do
    parent = self()
    on_attempt = fn event -> send(parent, {:attempt, event}) end

    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(529) |> Req.Test.json(%{"detail" => "overloaded"})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "model" => "jev-1.14.0",
        "answers" => %{
          "private_request" => %{"type" => "noul", "noul" => 0.3},
          "private_disclosure" => %{"type" => "noul", "noul" => 0.9}
        },
        "usage" => %{"input_tokens" => 5, "output_tokens" => 1}
      })
    end)

    assert {:ok, config} = JevDecisions.new(api_key: "synthetic-jev-key", model: "jev-1.14.0")

    assert {:ok, result} =
             JevDecisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               sleep: fn _ms -> :ok end,
               on_attempt: on_attempt
             )

    assert result.attempts == 2
    assert_received {:attempt, %{phase: :finished, ordinal: 1, outcome: :failed} = first}
    assert first.error_code in [:unavailable, :rate_limited, :retryable]
    assert_received {:attempt, %{phase: :finished, ordinal: 2, outcome: :succeeded}}
  end

  test "openai all-refused preserves authenticated model and usage" do
    parent = self()
    on_attempt = fn event -> send(parent, {:attempt, event}) end

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "model" => "gpt-6-luna",
        "answers" => [
          %{"type" => "refusal", "name" => "private_request"},
          %{"type" => "refusal", "name" => "private_disclosure"}
        ],
        "usage" => %{"input_tokens" => 10, "output_tokens" => 0, "total_tokens" => 10}
      })
    end)

    assert {:ok, config} =
             OpenAIDecisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    assert {:error, :refused} =
             OpenAIDecisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               on_attempt: on_attempt
             )

    assert_received {:attempt, %{phase: :started, ordinal: 1}}

    assert_received {:attempt,
                     %{phase: :finished, ordinal: 1, outcome: :failed, error_code: :refused} =
                       finished}

    assert finished.model == "gpt-6-luna"
    assert finished.usage == %{input_tokens: 10, output_tokens: 0, total_tokens: 10}
    assert finished.probabilities == nil
  end

  test "openai conflicting duplicates are excluded from partial, uniquely valid retained" do
    parent = self()
    on_attempt = fn event -> send(parent, {:attempt, event}) end

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "model" => "gpt-6-luna",
        "answers" => [
          %{"type" => "predicate", "name" => "private_request", "probability" => 0.3},
          %{"type" => "predicate", "name" => "private_disclosure", "probability" => 0.7},
          %{"type" => "predicate", "name" => "private_disclosure", "probability" => 0.9}
        ],
        "usage" => %{"input_tokens" => 7, "output_tokens" => 1, "total_tokens" => 8}
      })
    end)

    assert {:ok, config} =
             OpenAIDecisions.new(api_key: "synthetic-openai-key", model: "gpt-6-luna")

    assert {:error, :invalid_result} =
             OpenAIDecisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               on_attempt: on_attempt
             )

    assert_received {:attempt, %{phase: :started, ordinal: 1}}

    assert_received {:attempt,
                     %{
                       phase: :finished,
                       ordinal: 1,
                       outcome: :failed,
                       error_code: :invalid_result
                     } = finished}

    assert finished.probabilities == %{"private_request" => 0.3}
    assert finished.usage == %{input_tokens: 7, output_tokens: 1, total_tokens: 8}
  end

  test "complete probabilities are usable without a returned model and retain a model when reported" do
    nouls = Map.new(@questions, &{&1.id, %{"type" => "noul", "noul" => 0.8}})

    predicates =
      Enum.map(@questions, &%{"type" => "predicate", "name" => &1.id, "probability" => 0.8})

    for {provider, answers} <- [
          {OpenAIDecisions, predicates},
          {JevDecisions, nouls},
          {GoogleDecisions, nouls}
        ],
        actual <- [nil, "returned-model"] do
      {:ok, config} = provider.new(api_key: "fixture-key", model: hd(provider.models()))

      reply =
        if actual, do: %{"answers" => answers, "model" => actual}, else: %{"answers" => answers}

      Req.Test.expect(__MODULE__, &Req.Test.json(&1, reply))

      assert {:ok, result} =
               provider.evaluate(config, "test", @questions, plug: {Req.Test, __MODULE__})

      assert result.model == actual
      assert result.probabilities == %{"private_request" => 0.8, "private_disclosure" => 0.8}
    end
  end

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end
end
