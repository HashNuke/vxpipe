defmodule Vxpipe.CallEngine.Usage.TelephonyAttempt do
  @moduledoc false

  alias Vxpipe.CallEngine.Usage.{Observation, ProviderContext, TelephonyProjection}

  @terminal_outcomes [:succeeded, :failed, :cancelled, :unknown]

  @derive {Inspect,
           only: [
             :attempt_id,
             :call_id,
             :participant_id,
             :provider,
             :connected_at,
             :terminal?
           ]}
  @enforce_keys [
    :attempt_id,
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :provider,
    :identified?,
    :connected_at,
    :connected_provenance,
    :terminal?
  ]
  defstruct @enforce_keys

  @type evidence_provenance :: :provider_reported | :locally_measured

  @type t :: %__MODULE__{
          attempt_id: String.t(),
          tenant_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          provider: ProviderContext.t(),
          identified?: boolean(),
          connected_at: DateTime.t() | nil,
          connected_provenance: evidence_provenance() | nil,
          terminal?: boolean()
        }

  @spec start(map(), String.t(), ProviderContext.t(), DateTime.t()) ::
          {:ok, t(), [Observation.t()]} | {:error, :invalid_telephony_usage}
  def start(identity, attempt_id, %ProviderContext{} = provider, %DateTime{} = observed_at)
      when is_map(identity) and is_binary(attempt_id) do
    with {:ok, fields} <- identity_fields(identity),
         attempt = new_attempt(fields, attempt_id, provider),
         {:ok, observations} <- TelephonyProjection.started(attempt, observed_at) do
      {:ok, attempt, observations}
    else
      _invalid -> {:error, :invalid_telephony_usage}
    end
  end

  def start(_identity, _attempt_id, _provider, _observed_at),
    do: {:error, :invalid_telephony_usage}

  @spec identify(t(), String.t(), String.t() | nil, DateTime.t()) ::
          {:ok, t(), [Observation.t()]} | {:error, :invalid_telephony_usage}
  def identify(
        %__MODULE__{terminal?: false} = attempt,
        operation_id,
        session_id,
        %DateTime{} = observed_at
      ) do
    with true <- identifier?(operation_id),
         true <- compatible_identifier?(attempt.provider.operation_id, operation_id),
         true <- compatible_identifier?(attempt.provider.session_id, session_id),
         {:ok, provider} <- provider_with_identifiers(attempt.provider, operation_id, session_id),
         attempt = %{attempt | provider: provider},
         {:ok, observations} <- identified_observations(attempt, observed_at) do
      {:ok, %{attempt | identified?: true}, observations}
    else
      _invalid -> {:error, :invalid_telephony_usage}
    end
  end

  def identify(%__MODULE__{} = attempt, _operation_id, _session_id, %DateTime{}),
    do: {:ok, attempt, []}

  @spec connect(t(), DateTime.t(), keyword()) :: {t(), [Observation.t()]}
  def connect(%__MODULE__{terminal?: true} = attempt, %DateTime{}, options)
      when is_list(options),
      do: {attempt, []}

  def connect(
        %__MODULE__{connected_at: %DateTime{}, connected_provenance: :locally_measured} = attempt,
        %DateTime{} = observed_at,
        options
      )
      when is_list(options) do
    case evidence(options) do
      {:ok, evidence} ->
        if Keyword.fetch!(evidence, :provenance) == :provider_reported do
          {%{attempt | connected_at: observed_at, connected_provenance: :provider_reported}, []}
        else
          {attempt, []}
        end

      {:error, :invalid_evidence} ->
        {attempt, []}
    end
  end

  def connect(%__MODULE__{connected_at: %DateTime{}} = attempt, %DateTime{}, options)
      when is_list(options),
      do: {attempt, []}

  def connect(%__MODULE__{} = attempt, %DateTime{} = observed_at, options)
      when is_list(options) do
    with {:ok, evidence} <- evidence(options),
         {:ok, observations} <- TelephonyProjection.connected(attempt, observed_at, evidence) do
      attempt = %{
        attempt
        | connected_at: observed_at,
          connected_provenance: Keyword.fetch!(evidence, :provenance)
      }

      {attempt, observations}
    else
      _invalid -> {attempt, []}
    end
  end

  @spec finish(t(), Observation.outcome(), DateTime.t(), keyword()) ::
          {t(), {:ok, [Observation.t()]} | {:error, :invalid_telephony_usage}}
  def finish(%__MODULE__{terminal?: true} = attempt, outcome, %DateTime{}, options)
      when outcome in @terminal_outcomes and is_list(options),
      do: {attempt, {:ok, []}}

  def finish(%__MODULE__{} = attempt, outcome, %DateTime{} = observed_at, options)
      when outcome in @terminal_outcomes and is_list(options) do
    with {:ok, evidence} <- evidence(options),
         {:ok, observations} <-
           TelephonyProjection.terminal(attempt, outcome, observed_at, evidence) do
      {%{attempt | terminal?: true}, {:ok, observations}}
    else
      _invalid -> {attempt, {:error, :invalid_telephony_usage}}
    end
  end

  defp identity_fields(identity) do
    fields =
      Map.take(identity, [:tenant_id, :call_id, :room_id, :incarnation_id, :participant_id])

    if map_size(fields) == 5 and Enum.all?(fields, fn {_key, value} -> identifier?(value) end) do
      {:ok, fields}
    else
      {:error, :invalid_identity}
    end
  end

  defp new_attempt(fields, attempt_id, provider) do
    %__MODULE__{
      attempt_id: attempt_id,
      tenant_id: fields.tenant_id,
      call_id: fields.call_id,
      room_id: fields.room_id,
      incarnation_id: fields.incarnation_id,
      participant_id: fields.participant_id,
      provider: provider,
      identified?: not is_nil(provider.operation_id) or not is_nil(provider.session_id),
      connected_at: nil,
      connected_provenance: nil,
      terminal?: false
    }
  end

  defp identified_observations(%{identified?: true}, _observed_at), do: {:ok, []}

  defp identified_observations(attempt, observed_at) do
    TelephonyProjection.identified(attempt, observed_at)
  end

  defp provider_with_identifiers(provider, operation_id, session_id) do
    ProviderContext.new(
      name: provider.name,
      integration_id: provider.integration_id,
      model: provider.model,
      voice: provider.voice,
      request_id: provider.request_id,
      operation_id: operation_id || provider.operation_id,
      session_id: session_id || provider.session_id
    )
  end

  defp compatible_identifier?(_current, nil), do: true
  defp compatible_identifier?(nil, candidate), do: identifier?(candidate)
  defp compatible_identifier?(current, current), do: true
  defp compatible_identifier?(_current, _candidate), do: false

  defp evidence(options) do
    with {:ok, options} <-
           Keyword.validate(options,
             provenance: nil,
             delivery_id: nil,
             source_sequence: nil,
             duration: :derive
           ),
         provenance when provenance in [:provider_reported, :locally_measured] <-
           Keyword.fetch!(options, :provenance),
         duration when duration in [:derive, :unavailable] <- Keyword.fetch!(options, :duration) do
      {:ok, options}
    else
      _invalid -> {:error, :invalid_evidence}
    end
  end

  defp identifier?(value) do
    is_binary(value) and String.trim(value) != "" and byte_size(value) <= 256
  end
end
