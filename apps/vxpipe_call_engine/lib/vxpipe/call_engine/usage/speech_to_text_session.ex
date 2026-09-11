defmodule Vxpipe.CallEngine.Usage.SpeechToTextSession do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal

  alias Vxpipe.CallEngine.Usage.{Observation, ProviderContext, SpeechToTextProjection}

  @derive {Inspect,
           only: [
             :attempt_id,
             :service_interval_id,
             :call_id,
             :activation_id,
             :provider,
             :provider_evidence?,
             :start_emitted?,
             :terminal?
           ]}
  @enforce_keys [
    :identity,
    :attempt_id,
    :service_interval_id,
    :call_id,
    :activation_id,
    :provider,
    :provider_evidence?,
    :started_at,
    :started_source_sequence,
    :start_emitted?,
    :terminal?,
    :finalized_turns
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          identity: map(),
          attempt_id: String.t(),
          service_interval_id: String.t(),
          call_id: String.t(),
          activation_id: String.t() | nil,
          provider: ProviderContext.t(),
          provider_evidence?: boolean(),
          started_at: DateTime.t() | nil,
          started_source_sequence: non_neg_integer() | nil,
          start_emitted?: boolean(),
          terminal?: boolean(),
          finalized_turns: MapSet.t(non_neg_integer())
        }

  @spec start(
          map(),
          String.t(),
          String.t(),
          String.t(),
          String.t() | nil,
          ProviderContext.t()
        ) :: t()
  def start(
        identity,
        attempt_id,
        service_interval_id,
        call_id,
        activation_id,
        %ProviderContext{} = provider
      )
      when is_map(identity) and is_binary(attempt_id) and is_binary(service_interval_id) and
             is_binary(call_id) and (is_binary(activation_id) or is_nil(activation_id)) do
    %__MODULE__{
      identity: identity,
      attempt_id: attempt_id,
      service_interval_id: service_interval_id,
      call_id: call_id,
      activation_id: activation_id,
      provider: provider,
      provider_evidence?: false,
      started_at: nil,
      started_source_sequence: nil,
      start_emitted?: false,
      terminal?: false,
      finalized_turns: MapSet.new()
    }
  end

  @spec accept_input(t(), DateTime.t()) :: {t(), [Observation.t()]}
  def accept_input(%__MODULE__{terminal?: false} = session, %DateTime{} = observed_at) do
    session = put_start_evidence(session, observed_at, nil)
    session = %{session | provider_evidence?: true}

    emit_start(session)
  end

  def accept_input(%__MODULE__{} = session, %DateTime{}), do: {session, []}

  @spec observe_signal(t(), Signal.t(), boolean(), DateTime.t()) ::
          {t(), [Observation.t()]}
  def observe_signal(
        %__MODULE__{terminal?: false} = session,
        %Signal{} = signal,
        retain_text_measurement?,
        %DateTime{} = observed_at
      )
      when is_boolean(retain_text_measurement?) do
    session = observe_provider_evidence(session, signal, observed_at)
    {session, started} = maybe_emit_start(session, signal)

    if final_turn?(session, signal) do
      session = %{
        session
        | finalized_turns: MapSet.put(session.finalized_turns, signal.provider_turn_index)
      }

      observations =
        SpeechToTextProjection.final_turn(
          session,
          signal,
          retain_text_measurement?,
          observed_at
        )

      {session, started ++ observations}
    else
      {session, started}
    end
  end

  def observe_signal(
        %__MODULE__{} = session,
        %Signal{},
        retain_text_measurement?,
        %DateTime{}
      )
      when is_boolean(retain_text_measurement?),
      do: {session, []}

  @spec finish(t(), :succeeded | :failed | :cancelled, DateTime.t()) ::
          {t(), [Observation.t()]}
  def finish(
        %__MODULE__{terminal?: false, provider_evidence?: true} = session,
        outcome,
        observed_at
      )
      when outcome in [:succeeded, :failed, :cancelled] and is_struct(observed_at, DateTime) do
    {session, started} = emit_start(session)
    session = %{session | terminal?: true}
    {session, started ++ SpeechToTextProjection.terminal(session, outcome, observed_at)}
  end

  def finish(%__MODULE__{terminal?: false} = session, outcome, %DateTime{})
      when outcome in [:succeeded, :failed, :cancelled],
      do: {%{session | terminal?: true}, []}

  def finish(%__MODULE__{} = session, outcome, %DateTime{})
      when outcome in [:succeeded, :failed, :cancelled],
      do: {session, []}

  defp observe_provider_evidence(session, signal, observed_at) do
    provider = %{
      session.provider
      | request_id: signal.request_id || session.provider.request_id
    }

    session = put_start_evidence(session, observed_at, signal.provider_sequence)
    %{session | provider: provider, provider_evidence?: true}
  end

  defp put_start_evidence(%{started_at: nil} = session, observed_at, source_sequence) do
    %{session | started_at: observed_at, started_source_sequence: source_sequence}
  end

  defp put_start_evidence(session, _observed_at, _source_sequence), do: session

  defp maybe_emit_start(session, %Signal{kind: :connected}), do: {session, []}
  defp maybe_emit_start(session, %Signal{}), do: emit_start(session)

  defp emit_start(%{start_emitted?: false, started_at: %DateTime{} = started_at} = session) do
    session = %{session | start_emitted?: true}

    observations = SpeechToTextProjection.started(session, started_at)

    {session, observations}
  end

  defp emit_start(session), do: {session, []}

  defp final_turn?(session, %Signal{kind: :turn_ended, provider_turn_index: turn_index})
       when is_integer(turn_index) and turn_index >= 0 do
    not MapSet.member?(session.finalized_turns, turn_index)
  end

  defp final_turn?(_session, _signal), do: false
end
