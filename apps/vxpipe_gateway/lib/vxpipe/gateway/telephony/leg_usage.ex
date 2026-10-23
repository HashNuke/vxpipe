defmodule Vxpipe.Gateway.Telephony.LegUsage do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Event, OutboundLegRequest, Submission}
  alias Vxpipe.CallEngine.Usage.{Observation, ProviderContext, TelephonyAttempt}

  alias Vxpipe.Gateway.Telephony.{
    CallEngineUsageReporter,
    ConfiguredService,
    LegUsageEvent,
    MediaBinding,
    UsageReporter
  }

  @default_reporter {CallEngineUsageReporter, []}

  @derive {Inspect, only: [:attempt]}
  @enforce_keys [:attempt, :clock, :reporter]
  defstruct @enforce_keys ++ [observations: []]

  @type t :: %__MODULE__{
          attempt: TelephonyAttempt.t(),
          clock: (-> DateTime.t()),
          reporter: UsageReporter.reporter(),
          observations: [Observation.t()]
        }

  @spec start_outgoing(
          OutboundLegRequest.t(),
          ConfiguredService.t(),
          String.t(),
          keyword()
        ) :: t() | nil
  def start_outgoing(
        %OutboundLegRequest{} = request,
        %ConfiguredService{} = service,
        leg_id,
        options
      )
      when is_binary(leg_id) and is_list(options) do
    start(
      %{
        tenant_id: request.tenant_id,
        call_id: request.call_id,
        room_id: request.room_id,
        incarnation_id: request.incarnation_id,
        participant_id: request.participant_id
      },
      leg_id,
      provider(service, nil, nil),
      options
    )
  end

  @spec start_incoming(MediaBinding.t(), keyword()) :: t() | nil
  def start_incoming(%MediaBinding{} = binding, options) when is_list(options) do
    start(
      %{
        tenant_id: binding.tenant_id,
        call_id: binding.call_id,
        room_id: binding.room_id,
        incarnation_id: binding.incarnation_id,
        participant_id: binding.participant_id
      },
      binding.client_state_leg_id,
      provider(
        binding.provider,
        binding.service_id,
        binding.provider_call_leg_id,
        binding.provider_call_session_id
      ),
      options
    )
  end

  @spec identify(t() | nil, Submission.t()) :: t() | nil
  def identify(%__MODULE__{} = usage, %Submission{} = submission) do
    identify(
      usage,
      submission.provider_call_leg_id,
      submission.provider_call_session_id,
      now(usage)
    )
  end

  def identify(nil, %Submission{}), do: nil

  @spec observe(t() | nil, Event.t()) :: t() | nil
  def observe(%__MODULE__{} = usage, %Event{} = event) do
    {observed_at, provenance} = LegUsageEvent.observation_time(event, now(usage))

    usage =
      identify(
        usage,
        event.provider_call_leg_id,
        event.provider_call_session_id,
        observed_at
      )

    case event.kind do
      kind when kind in [:answered, :media_started] ->
        connect(usage, event, observed_at, provenance)

      :ended ->
        finish(
          usage,
          LegUsageEvent.terminal_outcome(connected?(usage), event.end_reason),
          observed_at,
          LegUsageEvent.evidence(event, provenance)
        )

      _other ->
        usage
    end
  end

  def observe(nil, %Event{}), do: nil

  @spec fail(t() | nil, :failed | :cancelled | :unknown) :: t() | nil
  def fail(%__MODULE__{} = usage, outcome) when outcome in [:failed, :cancelled, :unknown] do
    finish(usage, outcome, now(usage),
      provenance: :locally_measured,
      duration: :unavailable
    )
  end

  def fail(nil, outcome) when outcome in [:failed, :cancelled, :unknown], do: nil

  @doc "Persists retained terminal usage independently of the live room; safe to retry."
  @spec persist_final(t() | nil, keyword()) ::
          :ok | {:error, :usage_not_final | :usage_persistence_unavailable}
  def persist_final(usage, options \\ [])

  def persist_final(%__MODULE__{attempt: %{terminal?: true}} = usage, options)
      when is_list(options) do
    if Enum.any?(usage.observations, &(&1.outcome in [:succeeded, :failed, :cancelled, :unknown])) do
      Enum.reduce_while(usage.observations, :ok, fn observation, :ok ->
        case persist_observation(observation, options) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    else
      {:error, :usage_not_final}
    end
  end

  def persist_final(_usage, _options), do: {:error, :usage_not_final}

  defp persist_observation(observation, options) do
    case Vxpipe.Calls.store_usage_observation(observation, options) do
      {:ok, %Observation{observed_at: %DateTime{}} = stored} ->
        if DateTime.compare(stored.observed_at, observation.observed_at) == :eq and
             %{stored | observed_at: observation.observed_at} == observation,
           do: :ok,
           else: {:error, :usage_persistence_unavailable}

      _unacknowledged ->
        {:error, :usage_persistence_unavailable}
    end
  rescue
    _exception -> {:error, :usage_persistence_unavailable}
  catch
    _kind, _reason -> {:error, :usage_persistence_unavailable}
  end

  defp start(identity, leg_id, {:ok, provider}, options) do
    clock = Keyword.get(options, :usage_clock, fn -> DateTime.utc_now(:millisecond) end)
    reporter = Keyword.get(options, :usage_reporter, @default_reporter)
    observed_at = safe_now(clock)

    case TelephonyAttempt.start(identity, leg_id, provider, observed_at) do
      {:ok, attempt, observations} ->
        report(%__MODULE__{attempt: attempt, clock: clock, reporter: reporter}, observations)

      {:error, :invalid_telephony_usage} ->
        nil
    end
  end

  defp start(_identity, _leg_id, {:error, :invalid_provider_context}, _options), do: nil

  defp provider(%ConfiguredService{} = service, operation_id, session_id) do
    provider(
      service.identity.provider,
      service.identity.service_id,
      operation_id,
      session_id
    )
  end

  defp provider(provider, integration_id, operation_id, session_id) do
    ProviderContext.new(
      name: Atom.to_string(provider),
      integration_id: integration_id,
      operation_id: operation_id,
      session_id: session_id
    )
  end

  defp identify(usage, nil, _session_id, _observed_at), do: usage

  defp identify(%__MODULE__{} = usage, operation_id, session_id, observed_at) do
    case TelephonyAttempt.identify(usage.attempt, operation_id, session_id, observed_at) do
      {:ok, attempt, observations} ->
        report(%{usage | attempt: attempt}, observations)

      {:error, :invalid_telephony_usage} ->
        usage
    end
  end

  defp connect(%__MODULE__{} = usage, event, observed_at, provenance) do
    {attempt, observations} =
      TelephonyAttempt.connect(
        usage.attempt,
        observed_at,
        LegUsageEvent.evidence(event, provenance)
      )

    report(%{usage | attempt: attempt}, observations)
  end

  defp finish(%__MODULE__{} = usage, outcome, observed_at, options) do
    case TelephonyAttempt.finish(usage.attempt, outcome, observed_at, options) do
      {attempt, {:ok, observations}} ->
        report(%{usage | attempt: attempt}, observations)

      {_attempt, {:error, :invalid_telephony_usage}} ->
        usage
    end
  end

  defp report(usage, observations) do
    :ok = UsageReporter.report(usage.reporter, observations)
    %{usage | observations: usage.observations ++ observations}
  end

  defp connected?(%__MODULE__{attempt: %{connected_at: %DateTime{}}}), do: true
  defp connected?(%__MODULE__{}), do: false

  defp now(%__MODULE__{clock: clock}), do: safe_now(clock)

  defp safe_now(clock) do
    case clock.() do
      %DateTime{} = observed_at -> observed_at
      _invalid -> DateTime.utc_now(:millisecond)
    end
  rescue
    _exception -> DateTime.utc_now(:millisecond)
  catch
    _kind, _reason -> DateTime.utc_now(:millisecond)
  end
end
