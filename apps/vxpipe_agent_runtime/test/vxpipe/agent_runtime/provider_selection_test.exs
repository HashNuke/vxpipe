defmodule Vxpipe.AgentRuntime.ProviderSelectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.ProviderSelection

  test "translates provider-local Google selection and pins endpoint and header authentication" do
    assert {:ok, options} =
             ProviderSelection.translate(
               "google",
               "gemini-2.5-flash",
               %{"temperature" => 0.2, "max_tokens" => 256},
               %{"google_thinking_budget" => 1024}
             )

    assert Keyword.fetch!(options, :model) == "google:gemini-2.5-flash"
    assert Keyword.fetch!(options, :streaming) == true
    generation = Keyword.fetch!(options, :generation_options)
    assert Keyword.fetch!(generation, :temperature) == 0.2

    assert Keyword.fetch!(generation, :base_url) ==
             "https://generativelanguage.googleapis.com/v1beta"

    provider = Keyword.fetch!(generation, :provider_options)
    assert Keyword.fetch!(provider, :google_auth_header)
    assert Keyword.fetch!(provider, :google_thinking_budget) == 1024
    refute Keyword.has_key?(options, :api_key)
  end

  test "rejects private transport options, unsupported providers and conflicting thinking controls" do
    for {provider, model, common, specific} <- [
          {"req_llm", "google:gemini-2.5-flash", %{}, %{}},
          {"google", "openai:gpt-5", %{}, %{}},
          {"google", "gemini-2.5-flash", %{"api_key" => "private-marker"}, %{}},
          {"google", "gemini-2.5-flash", %{"temperature" => -1}, %{}},
          {"google", "gemini-2.5-flash", %{}, %{"google_auth_header" => false}},
          {"google", "gemini-2.5-flash", %{}, %{"base_url" => "https://private-marker"}},
          {"google", "gemini-2.5-flash", %{},
           %{"google_thinking_budget" => 1024, "google_thinking_level" => "high"}}
        ] do
      assert {:error, :invalid_provider_selection} =
               ProviderSelection.translate(provider, model, common, specific)
    end
  end
end
