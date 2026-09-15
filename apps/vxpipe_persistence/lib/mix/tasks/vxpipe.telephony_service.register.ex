defmodule Mix.Tasks.Vxpipe.TelephonyService.Register do
  use Mix.Task

  alias Vxpipe.Calls.TelephonyServices
  alias Vxpipe.Persistence.CLI

  @shortdoc "Registers tenant Telnyx service metadata against a provisioned credential"
  @requirements ["app.config"]

  @moduledoc """
  Registers a tenant Telnyx service through a trusted operator session.

      mix vxpipe.telephony_service.register --tenant TENANT_KEY --file service.json

  The JSON object contains name, ingress_key, provider (telnyx), provider_connection_id,
  credential_id and public_key. Optional fields are outbound_number,
  answering_machine_detection (disabled or detect), media_token_ttl_ms and
  webhook_tolerance_seconds. The existing provider credential must belong to the same
  tenant/provider and be active and readable. Output contains public binding IDs only.
  Secret fields, adapter modules and public origins are not service metadata.
  """

  @impl true
  def run(arguments) do
    options = options!(arguments)
    attributes = metadata!(Keyword.fetch!(options, :file))
    CLI.ensure_ready!()

    service =
      options
      |> Keyword.fetch!(:tenant)
      |> TelephonyServices.register(attributes)
      |> CLI.unwrap!()

    CLI.output!(%{
      "service_id" => service.id,
      "tenant_key" => service.tenant_key,
      "name" => service.name,
      "provider" => service.provider,
      "ingress_key" => service.ingress_key,
      "credential_id" => service.credential_id
    })
  end

  defp options!(arguments) do
    CLI.options!(arguments, [tenant: :string, file: :string], [:tenant, :file])
  rescue
    _error in Mix.Error ->
      Mix.raise("invalid service registration arguments; require --tenant and --file")
  end

  defp metadata!(path) do
    with {:ok, input} when is_binary(input) and byte_size(input) <= 16_384 <-
           File.open(path, [:read, :binary], &IO.binread(&1, 16_385)),
         {:ok, attributes} when is_map(attributes) <- JSON.decode(input) do
      attributes
    else
      _invalid ->
        Mix.raise("service metadata file must contain a JSON object of at most 16384 bytes")
    end
  end
end
