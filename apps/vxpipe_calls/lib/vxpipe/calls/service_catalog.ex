defmodule Vxpipe.Calls.ServiceCatalog do
  @moduledoc "Configured services visible to a call-spec author in one tenant."

  alias Vxpipe.CallEngine.ModelCatalog

  alias Vxpipe.Calls.{
    CallSpecAuthorization,
    EffectiveServiceBindings,
    SavedMCPCatalog,
    UserAuthorization
  }

  alias Vxpipe.Identity.Principal
  alias Vxpipe.Providers.Registry

  @capabilities %{
    "speech_to_text" => :stt,
    "output_speech_to_text" => :stt,
    "text_to_speech" => :tts,
    "speech_to_speech" => :sts,
    "model_inference" => :llm,
    "telephony" => :telephony
  }

  def list(authority, tenant, capability, options) do
    with :ok <- CallSpecAuthorization.authorize(authority, :read, tenant),
         :ok <- validate_capability(capability),
         {:ok, %{bindings: bindings}} <- EffectiveServiceBindings.list(tenant, options),
         {:ok, mcps} <- SavedMCPCatalog.records(tenant, options) do
      native =
        bindings
        |> Enum.filter(&(&1.status == :connected and visible?(authority, &1)))
        |> Enum.map(&native_service/1)

      services =
        (native ++ Enum.map(mcps, &mcp_service/1))
        |> Enum.filter(&(is_nil(capability) or capability in &1.capabilities))
        |> Enum.sort_by(&{&1.service, &1.kind, Map.get(&1, :credential_name, "")})

      {:ok, %{services: services}}
    end
  end

  defp validate_capability(nil), do: :ok
  defp validate_capability("tools"), do: :ok
  defp validate_capability(capability) when is_map_key(@capabilities, capability), do: :ok
  defp validate_capability(_), do: {:error, :invalid_capability}

  defp visible?(%Principal{} = principal, %{source: :platform}),
    do: UserAuthorization.platform_authoring_allowed?(principal)

  defp visible?(_authority, _binding), do: true

  defp native_service(binding) do
    installed = Map.fetch!(Registry.catalog(), binding.provider)

    %{
      kind: "provider",
      service: binding.provider,
      provider_id: binding.provider,
      name: ModelCatalog.provider_name(binding.provider),
      credential_name: binding.name,
      source: binding.source,
      capabilities:
        @capabilities
        |> Enum.filter(fn {_name, kind} -> kind in installed end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()
    }
  end

  defp mcp_service(record) do
    %{
      kind: "mcp",
      service: record.id,
      name: record.server_name,
      source: :tenant,
      capabilities: ["tools"]
    }
  end
end
