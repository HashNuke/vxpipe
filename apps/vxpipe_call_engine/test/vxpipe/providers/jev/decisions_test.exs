defmodule Vxpipe.Providers.Jev.DecisionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Jev.Decisions

  @questions [
    %{id: "private_request", question: "Is the caller asking about their own account?"},
    %{
      id: "private_disclosure",
      question: "Does this response disclose another patient's details?"
    }
  ]

  test "builds the official System One wire body without policy leakage" do
    assert {:ok, config} = Decisions.new(api_key: "synthetic-jev-key", model: "jev-1.14.0")
    refute inspect(config) =~ "synthetic-jev-key"

    assert {:ok, body} = Decisions.request_body(config, "caller: hello", @questions)

    assert body[:model] == "jev-1.14.0"
    assert body[:state] == "caller: hello"

    assert body[:questions] == %{
             "private_request" => %{
               type: "noul",
               instructions: "Is the caller asking about their own account?"
             },
             "private_disclosure" => %{
               type: "noul",
               instructions: "Does this response disclose another patient's details?"
             }
           }

    encoded = JSON.encode!(body)
    refute encoded =~ "required_answer"
    refute encoded =~ "threshold"
    refute encoded =~ "synthetic-jev-key"
  end

  test "successful batch maps exact named noul scores with actual model and usage" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/systemone"
      [auth] = Plug.Conn.get_req_header(conn, "authorization")
      assert auth == "Bearer synthetic-jev-key"

      body = JSON.decode!(Req.Test.raw_body(conn))
      assert body["model"] == "jev-1.14.0"

      assert %{
               "private_request" => %{"type" => "noul"},
               "private_disclosure" => %{"type" => "noul"}
             } =
               body["questions"]

      Req.Test.json(conn, %{
        "model" => "jev-1.14.0",
        "answers" => %{
          "private_request" => %{"type" => "noul", "noul" => 0.3},
          "private_disclosure" => %{"type" => "noul", "noul" => 0.9}
        },
        "usage" => %{"input_tokens" => 120, "output_tokens" => 12}
      })
    end)

    assert {:ok, config} = Decisions.new(api_key: "synthetic-jev-key", model: "jev-1.14.0")

    assert {:ok, result} =
             Decisions.evaluate(config, "caller: hello", @questions, plug: {Req.Test, __MODULE__})

    assert result.model == "jev-1.14.0"
    assert result.probabilities == %{"private_request" => 0.3, "private_disclosure" => 0.9}
    assert result.usage == %{input_tokens: 120, output_tokens: 12}
    assert result.attempts == 1
  end

  test "wrong types, coerced, missing or unknown answers are invalid" do
    cases = [
      %{
        "model" => "jev-1.14.0",
        "answers" => %{
          "private_request" => %{
            "type" => "choice",
            "choice" => "yes",
            "confidence" => 0.9,
            "probabilities" => %{}
          },
          "private_disclosure" => %{"type" => "noul", "noul" => 0.9}
        },
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      },
      %{
        "model" => "jev-1.14.0",
        "answers" => %{
          "private_request" => %{"type" => "noul", "noul" => "0.3"},
          "private_disclosure" => %{"type" => "noul", "noul" => 0.9}
        },
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      },
      %{
        "model" => "jev-1.14.0",
        "answers" => %{
          "private_request" => %{"type" => "noul", "noul" => 0.3}
        },
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      },
      %{
        "model" => "jev-1.14.0",
        "answers" => %{
          "private_request" => %{"type" => "noul", "noul" => 0.3},
          "private_disclosure" => %{"type" => "noul", "noul" => 0.9},
          "unknown_q" => %{"type" => "noul", "noul" => 0.1}
        },
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      },
      %{
        "model" => "jev-1.14.0",
        "answers" => %{
          "private_request" => %{"type" => "noul", "noul" => 2},
          "private_disclosure" => %{"type" => "noul", "noul" => 0.9}
        },
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      }
    ]

    for payload <- cases do
      Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, payload) end)
      assert {:ok, config} = Decisions.new(api_key: "synthetic-jev-key", model: "jev-1.14.0")

      assert {:error, :invalid_result} =
               Decisions.evaluate(config, "caller: hello", @questions,
                 plug: {Req.Test, __MODULE__}
               )
    end
  end

  test "one bounded retry on 529 or 503 then success; 529 is Jev-specific" do
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

    assert {:ok, config} = Decisions.new(api_key: "synthetic-jev-key", model: "jev-1.14.0")

    assert {:ok, result} =
             Decisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               sleep: fn _ms -> :ok end
             )

    assert result.attempts == 2
  end

  test "second retryable failure exhausts the single retry" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{"detail" => "rate limited"})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{"detail" => "rate limited"})
    end)

    assert {:ok, config} = Decisions.new(api_key: "synthetic-jev-key", model: "jev-1.14.0")

    assert {:error, :retry_exhausted} =
             Decisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               sleep: fn _ms -> :ok end
             )
  end

  test "no retry on auth or validation failures" do
    assert {:ok, config} = Decisions.new(api_key: "synthetic-jev-key", model: "jev-1.14.0")

    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"detail" => "bad key"})
    end)

    assert {:error, :unauthorized} =
             Decisions.evaluate(config, "caller: hello", @questions, plug: {Req.Test, __MODULE__})

    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"detail" => []})
    end)

    assert {:error, :invalid_result} =
             Decisions.evaluate(config, "caller: hello", @questions, plug: {Req.Test, __MODULE__})
  end

  test "oversize and invalid configuration never reach HTTP" do
    assert {:ok, config} = Decisions.new(api_key: "synthetic-jev-key", model: "jev-1.14.0")

    assert {:error, :oversized} =
             Decisions.evaluate(config, String.duplicate("x", 49_153), @questions,
               plug: {Req.Test, __MODULE__}
             )

    assert {:error, :invalid_configuration} = Decisions.new(api_key: "", model: "jev-1.14.0")

    assert {:error, :invalid_configuration} =
             Decisions.new(api_key: "synthetic-jev-key", model: "unknown")
  end

  test "expired deadline times out before any HTTP attempt" do
    assert {:ok, config} = Decisions.new(api_key: "synthetic-jev-key", model: "jev-1.14.0")
    past = System.monotonic_time(:millisecond) - 1

    assert {:error, :timeout} =
             Decisions.evaluate(config, "caller: hello", @questions,
               plug: {Req.Test, __MODULE__},
               deadline_ms: past
             )
  end

  test "pins the official Jev System One contract" do
    assert Decisions.models() == ["jev-1.14.0", "jev-latest"]
    assert Decisions.endpoint() == "https://api.typesafe.ai/v1/systemone"
  end

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end
end
