defmodule Vxpipe.Gateway.TestTelephonyServiceRepository do
  @moduledoc false

  alias Vxpipe.Calls.{
    ProviderCredential,
    ResolvedProviderCredential,
    ResolvedTelephonyService,
    TelephonyService,
    TelephonyServices
  }

  # Convert old fixture declarations into typed tenant records at the test boundary.
  # Production has no static-service configuration reader.
  def registry(options),
    do: Vxpipe.Gateway.Telephony.ServiceRegistry.init!(telephony_options(options))

  def ingress(options),
    do: Vxpipe.Gateway.HTTP.TelephonyIngressConfig.init(telephony_options(options))

  def endpoint(options), do: Vxpipe.Gateway.HTTP.Endpoint.init(endpoint_options(options))
  def router(options), do: Vxpipe.Gateway.HTTP.Router.init(endpoint_options(options))

  defp endpoint_options(options) do
    Keyword.update(options, :telephony, [], &telephony_options/1)
  end

  defp telephony_options(options) do
    {services, options} = Keyword.pop(options, :services, [])
    {available?, options} = Keyword.pop(options, :service_availability)
    Keyword.merge(options, options(services, available?))
  end

  def options(services, available? \\ nil) do
    snapshots = Enum.map(services, &snapshot/1)
    origin = services |> List.first([]) |> Keyword.get(:public_base_url)

    context =
      if is_function(available?, 0) do
        fn operation, arguments ->
          if available?.(),
            do: apply(__MODULE__, operation, [snapshots | arguments]),
            else: {:error, :repository_unavailable}
        end
      else
        snapshots
      end

    adapters =
      Map.new(services, fn options ->
        {Keyword.fetch!(options, :provider), Keyword.get(options, :adapter)}
      end)

    [
      public_base_url: origin,
      telephony_service_repository: {__MODULE__, context},
      provider_credential_repository: {__MODULE__, context},
      adapters: adapters
    ]
  end

  def snapshot(options) do
    {:tenant, tenant} = Keyword.fetch!(options, :scope)
    name = Keyword.fetch!(options, :id)
    provider = options |> Keyword.fetch!(:provider) |> Atom.to_string()
    credential_id = id({tenant, provider, :credential})

    {kind, payload, account} =
      case provider do
        "telnyx" ->
          {"api_key",
           %{
             "api_key" => Keyword.fetch!(options, :api_key),
             "public_key" => Keyword.fetch!(options, :public_key)
           }, Keyword.fetch!(options, :provider_connection_id)}

        "twilio" ->
          sid = Keyword.fetch!(options, :account_sid)

          {"account_sid_auth_token",
           %{"account_sid" => sid, "auth_token" => Keyword.fetch!(options, :auth_token)}, sid}
      end

    attributes = %{
      "name" => name,
      "ingress_key" => Keyword.fetch!(options, :ingress_key),
      "provider" => provider,
      "provider_connection_id" => account,
      "credential_id" => credential_id,
      "public_key" => Keyword.get(options, :public_key),
      "outbound_number" => Keyword.get(options, :outbound_number),
      "answering_machine_detection" =>
        options |> Keyword.get(:answering_machine_detection, :disabled) |> Atom.to_string(),
      "media_token_ttl_ms" => Keyword.get(options, :media_token_ttl_ms, 60_000),
      "webhook_tolerance_seconds" => Keyword.get(options, :webhook_tolerance_seconds, 300)
    }

    attributes =
      if provider == "telnyx",
        do:
          Map.merge(attributes, %{
            "credential_name" => "telnyx",
            "credential_id" => nil,
            "public_key" => nil
          }),
        else: attributes

    {:ok, service} = TelephonyService.new(tenant, attributes)

    service =
      if provider == "telnyx",
        do: %{
          service
          | credential_id: credential_id,
            credential_owner: {:tenant, tenant},
            public_key: Keyword.fetch!(options, :public_key)
        },
        else: service

    %ResolvedTelephonyService{
      service: %{service | id: id({tenant, name, :service})},
      credential: %ResolvedProviderCredential{
        credential: %ProviderCredential{
          id: credential_id,
          tenant_key: tenant,
          provider: provider,
          name: if(provider == "telnyx", do: "telnyx", else: "carrier"),
          owner: {:tenant, tenant},
          auth_kind: kind
        },
        payload: payload
      }
    }
  end

  def reference(options) do
    snapshot = snapshot(options)
    TelephonyServices.reference(snapshot.service)
  end

  def configured(options) do
    {:ok, service} =
      Vxpipe.Gateway.Telephony.ConfiguredService.from_snapshot(
        snapshot(options),
        Keyword.fetch!(options, :public_base_url),
        %{Keyword.fetch!(options, :provider) => Keyword.get(options, :adapter)}
      )

    service
  end

  def pin_plan(plan, options) do
    reference = reference(options)

    participants =
      Map.new(plan.participants, fn
        {key, %{connection: %{service: name}} = participant} when name == reference.name ->
          {key, %{participant | telephony_service: reference}}

        other ->
          other
      end)

    %{plan | participants: participants}
  end

  def fetch_by_ingress(context, ingress) when is_function(context, 2),
    do: context.(:fetch_by_ingress, [ingress])

  def fetch_by_ingress(snapshots, ingress) do
    case Enum.find(snapshots, &(&1.service.ingress_key == ingress)) do
      nil -> {:error, :service_not_found}
      snapshot -> {:ok, snapshot.service}
    end
  end

  def fetch_telnyx_application(context, application) when is_function(context, 2),
    do: context.(:fetch_telnyx_application, [application])

  def fetch_telnyx_application(snapshots, application) do
    case Enum.filter(
           snapshots,
           &(&1.service.provider == "telnyx" and &1.service.provider_connection_id == application)
         ) do
      [snapshot] ->
        {:ok, %{snapshot.service | credential_id: nil, credential_owner: nil, public_key: nil}}

      _missing_or_ambiguous ->
        {:error, :telephony_service_not_found}
    end
  end

  def resolve(context, scope, provider, name) when is_function(context, 2),
    do: context.(:resolve, [scope, provider, name])

  def resolve(snapshots, scope, provider, name) do
    owner = if is_binary(scope), do: {:tenant, scope}, else: scope

    case Enum.find(snapshots, fn snapshot ->
           credential = snapshot.credential.credential

           credential.owner == owner and credential.provider == provider and
             credential.name == name
         end) do
      nil -> {:error, :provider_credential_not_found}
      snapshot -> {:ok, snapshot.credential}
    end
  end

  def resolve(context, tenant, name) when is_function(context, 2),
    do: context.(:resolve, [tenant, name])

  def resolve(snapshots, tenant, name) do
    case Enum.find(snapshots, &(&1.service.tenant_key == tenant and &1.service.name == name)) do
      nil -> {:error, :provider_credential_unavailable}
      snapshot -> {:ok, snapshot}
    end
  end

  def with_active(snapshots, tenant, requirements, operation) do
    failed =
      Enum.find(requirements, fn requirement ->
        case resolve(snapshots, tenant, requirement.name) do
          {:ok, snapshot} ->
            not TelephonyServices.meets_requirement?(snapshot.service, requirement)

          _unavailable ->
            true
        end
      end)

    if failed,
      do: {:error, {:provider_credential_unavailable, failed.path}},
      else: operation.()
  end

  defp id(term) do
    <<a::32, b::16, _version::4, c::12, _variant::2, d::14, e::48, _rest::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary(term))

    <<h1::binary-size(8), h2::binary-size(4), h3::binary-size(4), h4::binary-size(4), h5::binary>> =
      Base.encode16(<<a::32, b::16, 4::4, c::12, 2::2, d::14, e::48>>, case: :lower)

    Enum.join([h1, h2, h3, h4, h5], "-")
  end
end
