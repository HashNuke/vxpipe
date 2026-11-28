defmodule Vxpipe.CallEngine.DecisionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.{Decisions, ProviderCredential, TestTenantCredentialSource}

  @providers [
    {"openai", "gpt-6-luna", "api.openai.com", "/v1/decisions"},
    {"google", "gemini-decision-1", "generativelanguage.googleapis.com", "/v1beta/decisions"},
    {"jev", "jev-1.14.0", "api.typesafe.ai", "/v1/systemone"}
  ]

  for {provider, model, host, path} <- @providers do
    test "a saved #{provider} integration dispatches a named question through the shared Decisions API" do
      provider = unquote(provider)
      model = unquote(model)
      selection = selection(provider, model)
      key = "synthetic-" <> provider
      credential = credential(provider, key)

      options =
        source_options(selection, credential, ProviderCredential.binding_identity(credential))

      assert {:ok, bound} = Decisions.bind("tenant", selection, options)
      assert_received {:tenant_credential_resolved, "tenant", ^provider, "review"}
      refute inspect(bound) =~ key

      evidence = %{"current" => %{"text" => "Can you help with my account?"}}
      questions = [%{id: "own_account", question: "Is it the caller's account?"}]

      plug = fn conn ->
        assert conn.host == unquote(host)
        assert conn.request_path == unquote(path)
        body = JSON.decode!(Req.Test.raw_body(conn))

        if provider == "google" do
          assert Plug.Conn.get_req_header(conn, "x-goog-api-key") == [key]
          assert body["model"] == "models/" <> model
        else
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer " <> key]
          assert body["model"] == model
        end

        assert (body["state"] || JSON.decode!(body["input"])) == evidence

        answers =
          if provider == "openai",
            do: [%{name: "own_account", type: "predicate", probability: 0.86}],
            else: %{own_account: %{type: "noul", noul: 0.86}}

        Req.Test.json(conn, %{answers: answers, model: "reported"})
      end

      assert {:ok,
              %{
                provider: ^provider,
                model: "reported",
                probabilities: %{"own_account" => 0.86},
                attempts: 1
              }} =
               Decisions.evaluate(bound, evidence, questions, plug: plug)

      refute_received {:tenant_credential_resolved, _, _, _}
    end
  end

  test "the narrowed selection rejects a replacement named credential, unusable auth and foreign capability kinds" do
    credential = credential("google", "synthetic-google")
    selection = selection("google", "gemini-decision-1")
    binding = ProviderCredential.binding_identity(credential)
    options = source_options(selection, credential, %{binding | "id" => "pinned-other"})

    assert {:error, :provider_credential_unavailable} =
             Decisions.bind("tenant", selection, options)

    for invalid <- [%{credential | auth_kind: "oauth2"}, %{credential | payload: %{}}] do
      assert {:error, :provider_credential_unavailable} =
               Decisions.bind("tenant", selection, source_options(selection, invalid, binding))
    end

    assert {:error, :unsupported_capability} =
             Decisions.bind("tenant", %{selection | kind: :model_inference}, options)
  end

  defp selection(provider, model) do
    {:ok, selection} =
      CapabilitySelection.new(
        %{provider: provider, model: model, credential_name: "review"},
        :decisions,
        []
      )

    selection
  end

  defp credential(provider, key) do
    %ProviderCredential{
      id: "saved-" <> provider,
      tenant_id: "tenant",
      owner: {:tenant, "tenant"},
      provider: provider,
      name: "review",
      version: 3,
      auth_kind: "api_key",
      payload: %{"api_key" => key}
    }
  end

  defp source_options(selection, credential, binding) do
    [
      credential_source:
        {TestTenantCredentialSource,
         {self(), %{{"tenant", selection.provider, "review"} => credential}}},
      credential_bindings: %{{selection.provider, "review"} => binding}
    ]
  end
end
