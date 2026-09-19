defmodule Vxpipe.Calls.TelephonyService do
  @moduledoc "Non-secret tenant carrier binding. Public origins and private auth are supplied separately."

  alias Vxpipe.Calls.{ProviderAuth, PublicId}

  @attributes [
    name: nil,
    ingress_key: nil,
    provider: nil,
    provider_connection_id: nil,
    credential_id: nil,
    credential_name: nil,
    public_key: nil,
    outbound_number: nil,
    answering_machine_detection: "disabled",
    media_token_ttl_ms: 60_000,
    webhook_tolerance_seconds: 300
  ]
  @input_keys Enum.map(@attributes, fn {key, _default} -> Atom.to_string(key) end)
  @enforce_keys [:id, :tenant_key]
  @derive {Inspect, only: [:id, :tenant_key, :name, :provider, :credential_id]}
  defstruct @enforce_keys ++
              Keyword.keys(@attributes) ++ [:credential_owner, :inserted_at, :updated_at]

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_key: String.t(),
          name: String.t(),
          ingress_key: String.t(),
          provider: String.t(),
          provider_connection_id: String.t(),
          credential_id: String.t() | nil,
          credential_name: String.t() | nil,
          credential_owner: :platform | {:tenant, String.t()} | nil,
          public_key: String.t() | nil,
          outbound_number: String.t() | nil,
          answering_machine_detection: :disabled | :detect,
          media_token_ttl_ms: pos_integer(),
          webhook_tolerance_seconds: non_neg_integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec new(String.t(), map()) :: {:ok, t()} | {:error, atom()}
  def new(tenant_key, input) when is_map(input) do
    if Enum.all?(Map.keys(input), &(&1 in @input_keys)) do
      attributes =
        Map.new(@attributes, fn {key, default} ->
          {key, Map.get(input, Atom.to_string(key), default)}
        end)

      service =
        attributes
        |> Map.merge(%{id: PublicId.uuid(), tenant_key: tenant_key})
        |> Map.update!(:answering_machine_detection, &detection/1)
        |> then(&struct!(__MODULE__, &1))

      with :ok <- validate(service), do: {:ok, service}
    else
      {:error, :invalid_telephony_service}
    end
  end

  def new(_tenant_key, _input), do: {:error, :invalid_telephony_service}

  @doc false
  def validate(%__MODULE__{} = service) do
    if ProviderAuth.tenant_key(service.tenant_key) == :ok and
         identifier(service.name) == :ok and identifier(service.ingress_key) == :ok and
         uuid?(service.id) and credential_binding?(service) and provider_metadata?(service) and
         phone_number?(service.outbound_number) and
         service.answering_machine_detection in [:disabled, :detect] and
         timer?(service.media_token_ttl_ms, 1) and timer?(service.webhook_tolerance_seconds, 0),
       do: :ok,
       else: {:error, :invalid_telephony_service}
  end

  defp credential_binding?(%{credential_name: nil} = service),
    do: uuid?(service.credential_id) and is_nil(service.credential_owner)

  defp credential_binding?(%{
         provider: "telnyx",
         credential_name: "telnyx",
         credential_id: nil,
         public_key: nil,
         credential_owner: nil
       }),
       do: true

  defp credential_binding?(%{provider: "telnyx", credential_name: "telnyx"} = service),
    do:
      uuid?(service.credential_id) and
        service.credential_owner in [:platform, {:tenant, service.tenant_key}] and
        ProviderAuth.telnyx_public_key?(service.public_key)

  defp credential_binding?(_service), do: false

  @doc false
  def credential_matches?(
        %__MODULE__{provider: "telnyx", credential_name: "telnyx", public_key: key},
        payload
      ),
      do: ProviderAuth.telnyx_public_key?(key) and Map.get(payload, "public_key") == key

  def credential_matches?(%__MODULE__{provider: "telnyx"}, _payload), do: true

  def credential_matches?(%__MODULE__{provider: "twilio", provider_connection_id: sid}, %{
        "account_sid" => sid
      }),
      do: true

  def credential_matches?(_service, _payload), do: false

  defp provider_metadata?(%{provider: "telnyx", credential_name: "telnyx"} = service),
    do: connection_id?(service.provider_connection_id)

  defp provider_metadata?(%{provider: "telnyx"} = service),
    do:
      connection_id?(service.provider_connection_id) and
        ProviderAuth.telnyx_public_key?(service.public_key)

  defp provider_metadata?(%{provider: "twilio"} = service),
    do:
      ProviderAuth.twilio_account_sid?(service.provider_connection_id) and
        is_nil(service.public_key)

  defp provider_metadata?(_service), do: false

  @doc false
  def identifier(value) do
    if is_binary(value) and byte_size(value) in 1..128 and
         Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9_-]*\z/, value),
       do: :ok,
       else: {:error, :invalid_telephony_service}
  end

  defp uuid?(value) when is_binary(value) do
    Regex.match?(
      ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/,
      value
    )
  end

  defp uuid?(_value), do: false

  defp connection_id?(value) do
    is_binary(value) and byte_size(value) in 1..128 and Regex.match?(~r/\A[\x21-\x7E]+\z/, value)
  end

  defp phone_number?(nil), do: true

  defp phone_number?(value) when is_binary(value),
    do: Regex.match?(~r/\A\+[1-9][0-9]{1,14}\z/, value)

  defp phone_number?(_value), do: false

  defp timer?(value, minimum),
    do: is_integer(value) and value >= minimum and value <= 2_147_483_647

  defp detection("disabled"), do: :disabled
  defp detection("detect"), do: :detect
  defp detection(_value), do: :invalid
end
