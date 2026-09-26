defmodule Vxpipe.Providers.OpenAI.GPTLiveUsageTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.OpenAI.GPTLiveUsage

  test "converts cumulative voice seconds to exact millisecond deltas" do
    usage = GPTLiveUsage.new("gpt-5.6")
    assert {:ok, usage, 1_250} = GPTLiveUsage.voice(usage, 1.25)
    assert {:ok, usage, 750} = GPTLiveUsage.voice(usage, 2)
    assert {:ok, usage, 0} = GPTLiveUsage.voice(usage, 1.5)
    assert {:error, :invalid_usage} = GPTLiveUsage.voice(usage, -1)
  end

  test "keeps backend tokens under a separate model identity and deduplicates responses" do
    usage = GPTLiveUsage.new("gpt-5.6")

    response = %{
      "id" => "resp_1",
      "usage" => %{"input_tokens" => 12, "output_tokens" => 7, "total_tokens" => 19}
    }

    assert {:ok, usage, report} = GPTLiveUsage.backend(usage, response)
    assert report == %{model: "gpt-5.6", input_tokens: 12, output_tokens: 7}
    assert {:ok, ^usage, nil} = GPTLiveUsage.backend(usage, response)
    assert {:error, :invalid_usage} = GPTLiveUsage.backend(usage, %{"id" => "resp_2"})
  end
end
