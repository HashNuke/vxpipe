defmodule Vxpipe.Providers.DecisionsTransportTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.{Google, Jev, OpenAI}

  @questions [
    %{id: "one", question: "Is this supported?"},
    %{id: "two", question: "Is this billing?"}
  ]

  for {adapter, model} <- [{Google.Decisions, "gemini-decision-1"}, {Jev.Decisions, "jev-1.14.0"}] do
    test "#{model} rejects ambiguous IDs in raw JSON and preserves independent scores" do
      adapter = unquote(adapter)
      {:ok, config} = adapter.new(api_key: "synthetic-key", model: unquote(model))

      raw =
        ~s({"model":"#{unquote(model)}","answers":{"one":{"type":"noul","noul":0.4},"one":{"type":"noul","noul":0.9},"two":{"type":"noul","noul":0.1}}})

      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, raw)
      end)

      assert {:error, :invalid_result} =
               adapter.evaluate(config, "Synthetic.", @questions, options())

      assert_received {:attempt, %{phase: :finished, probabilities: %{"two" => 0.1} = scores}}
      refute Map.has_key?(scores, "one")
    end
  end

  test "a long Retry-After ends the batch while preserving the failed request identity" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("retry-after", "15")
      |> Plug.Conn.put_resp_header("x-request-id", "request-429")
      |> Plug.Conn.put_status(429)
      |> Req.Test.json(%{})
    end)

    assert {:error, :retry_exhausted} = run_openai()
    assert_received {:attempt, %{phase: :finished, ordinal: 1, request_id: "request-429"}}
    refute_received {:backoff, _}
    refute_received {:attempt, %{ordinal: 2}}
  end

  test "a malformed delay uses bounded default backoff" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("retry-after", "-1")
      |> Plug.Conn.put_status(429)
      |> Req.Test.json(%{})
    end)

    assert {:error, :retry_exhausted} = run_openai()
    assert_received {:backoff, 50}
    assert_received {:attempt, %{phase: :finished, ordinal: 2}}
  end

  test "a single reported Gemini usage component survives normalization and attempt telemetry" do
    {:ok, config} = Google.Decisions.new(api_key: "synthetic-key", model: "gemini-decision-1")

    for {wire_key, normalized} <- [
          {"total_input_tokens", :input_tokens},
          {"total_tokens", :total_tokens}
        ] do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{
          "answers" => %{
            "one" => %{"type" => "noul", "noul" => 0.7},
            "two" => %{"type" => "noul", "noul" => 0.2}
          },
          "usage" => %{wire_key => 14}
        })
      end)

      assert {:ok, result} =
               Google.Decisions.evaluate(config, "Synthetic.", @questions, options())

      expected = %{normalized => 14}
      assert result.usage == expected
      assert_received {:attempt, %{phase: :finished, usage: ^expected}}
    end
  end

  test "all adapters accept the same structured event and put it into their vendor wire format" do
    event = %{"event" => "after_turn", "current" => %{"text" => "Synthetic."}}

    for {adapter, model} <- [
          {OpenAI.Decisions, "gpt-6-luna"},
          {Google.Decisions, "gemini-decision-1"},
          {Jev.Decisions, "jev-1.14.0"}
        ] do
      assert {:ok, config} = adapter.new(api_key: "test-key", model: model)
      assert {:ok, body} = adapter.request_body(config, event, @questions)
      wire = body |> JSON.encode!() |> JSON.decode!()

      if adapter == Jev.Decisions do
        assert wire["state"] == event
      else
        assert JSON.decode!(wire["input"]) == event
      end

      assert {:error, :invalid_configuration} =
               adapter.new(api_key: "test-key", model: model, endpoint: "https://example.invalid")
    end
  end

  defp run_openai do
    {:ok, config} = OpenAI.Decisions.new(api_key: "synthetic-key", model: "gpt-6-luna")
    OpenAI.Decisions.evaluate(config, "Synthetic.", @questions, options())
  end

  defp options do
    observer = self()

    [
      plug: {Req.Test, __MODULE__},
      on_attempt: &send(observer, {:attempt, &1}),
      sleep: &send(observer, {:backoff, &1}),
      deadline_ms: System.monotonic_time(:millisecond) + 1_000
    ]
  end
end
