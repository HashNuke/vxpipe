defmodule Vxpipe.CallEngine.Capability.SpeechToText.State do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Capability.SpeechToText.TransportConnector
  alias Vxpipe.CallEngine.MediaPolicy.{Snapshot, SpeechToTextDemand}
  alias Vxpipe.CallEngine.Readiness.{Provider, Resource}

  @maximum_audio_bytes 131_072

  @enforce_keys [
    :connection,
    :connector,
    :identity,
    :last_provider_sequence,
    :media_format,
    :owner,
    :policy,
    :policy_revision,
    :provider_module,
    :transport,
    :transport_module,
    :transport_options,
    :usage,
    :usage_context
  ]
  defstruct @enforce_keys ++ [readiness_generation: nil, readiness_status: :preparing]

  @type t :: %__MODULE__{
          connection: map(),
          connector: map() | nil,
          identity: map(),
          last_provider_sequence: integer(),
          media_format: map(),
          owner: pid(),
          policy: Snapshot.t() | nil,
          policy_revision: non_neg_integer() | nil,
          provider_module: module(),
          readiness_generation: reference(),
          readiness_status: :preparing | :ready | :failed,
          transport: pid() | nil,
          transport_module: module(),
          transport_options: keyword(),
          usage: nil | Vxpipe.CallEngine.Usage.SpeechToTextSession.t(),
          usage_context: nil | keyword()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :transport_start_failed, module()}
  def new(options) do
    identity = %{
      tenant_id: Keyword.fetch!(options, :tenant_id),
      room_id: Keyword.fetch!(options, :room_id),
      incarnation_id: Keyword.fetch!(options, :incarnation_id),
      participant_id: Keyword.fetch!(options, :participant_id),
      connection_id: Keyword.fetch!(options, :connection_id)
    }

    owner = Keyword.fetch!(options, :owner)
    {provider_module, provider_config} = Keyword.fetch!(options, :provider)
    {transport_module, transport_options} = Keyword.fetch!(options, :transport)
    connection = provider_module.connection_options(provider_config)

    case start_transport(transport_module, connection, transport_options) do
      {:ok, transport} ->
        {:ok,
         %__MODULE__{
           connection: connection,
           connector: nil,
           identity: identity,
           last_provider_sequence: -1,
           media_format: provider_module.media_format(provider_config),
           owner: owner,
           policy: nil,
           policy_revision: nil,
           provider_module: provider_module,
           readiness_generation: make_ref(),
           readiness_status: Provider.initial_status(provider_module),
           transport: transport,
           transport_module: transport_module,
           transport_options: transport_options,
           usage: nil,
           usage_context: Keyword.get(options, :usage)
         }}

      {:error, _reason} ->
        {:error, :transport_start_failed, provider_module}
    end
  end

  @spec send_audio(t(), AudioFrame.t()) ::
          :ok | {:error, :policy_denied | :unsupported_audio | :unavailable}
  def send_audio(%__MODULE__{} = state, %AudioFrame{} = frame) do
    cond do
      not supported_audio?(state, frame) ->
        {:error, :unsupported_audio}

      is_nil(state.transport) ->
        {:error, :policy_denied}

      true ->
        case safe_send_audio(state.transport_module, state.transport, frame.payload) do
          :ok -> :ok
          {:error, _reason} -> {:error, :unavailable}
        end
    end
  end

  @spec install_policy(t(), Snapshot.t()) ::
          {:ok, t()} | {:error, term(), t()}
  def install_policy(%__MODULE__{} = state, %Snapshot{} = snapshot) do
    case Snapshot.prepare(snapshot, state.policy) do
      {:ok, snapshot} -> apply_policy(state, snapshot)
      {:error, reason} -> {:error, reason, state}
    end
  end

  @spec close(t()) :: t()
  def close(%__MODULE__{connector: connector} = state) when is_map(connector) do
    :ok = TransportConnector.stop(connector)
    %{state | connector: nil, transport: nil} |> invalidate_readiness()
  end

  def close(%__MODULE__{transport: nil} = state), do: state

  def close(%__MODULE__{} = state) do
    _ = safe_close(state.transport_module, state.transport)
    %{state | transport: nil} |> invalidate_readiness()
  end

  @spec readiness(t()) :: {:ok, Resource.t(), :preparing | :ready | :failed}
  def readiness(%__MODULE__{} = state) do
    resource = %Resource{
      kind: :speech_to_text,
      scope: {:participant, state.identity.participant_id},
      binding: state.identity.connection_id,
      instance: self(),
      generation: state.readiness_generation,
      configuration:
        Resource.signature({
          state.provider_module,
          state.connection,
          state.media_format,
          state.transport_module,
          state.transport_options
        }),
      policy_interval: state.policy_revision,
      adapter: Vxpipe.CallEngine.Capability.SpeechToText
    }

    status =
      if state.readiness_status == :ready and state.transport == nil,
        do: :preparing,
        else: state.readiness_status

    {:ok, resource, status}
  end

  defp invalidate_readiness(state) do
    %{
      state
      | readiness_generation: make_ref(),
        readiness_status: Provider.initial_status(state.provider_module)
    }
  end

  defp apply_policy(%__MODULE__{policy: nil} = state, snapshot) do
    state = if demanded?(state, snapshot), do: state, else: close(state)
    {:ok, put_policy(state, snapshot)}
  end

  defp apply_policy(%__MODULE__{} = state, snapshot) do
    if state.policy_revision ==
         Snapshot.interval(snapshot, :speech_to_text, state.identity.participant_id) do
      {:ok, %{state | policy: snapshot}}
    else
      replace_session(state, snapshot)
    end
  end

  defp replace_session(state, snapshot) do
    state = close(state)

    if demanded?(state, snapshot) do
      case TransportConnector.start(
             state.transport_module,
             state.connection,
             state.transport_options
           ) do
        {:ok, connector} -> {:ok, %{put_policy(state, snapshot) | connector: connector}}
        {:error, _reason} -> {:error, :transport_start_failed, state}
      end
    else
      {:ok, put_policy(state, snapshot)}
    end
  end

  defp put_policy(state, snapshot) do
    %{
      state
      | last_provider_sequence: -1,
        policy: snapshot,
        policy_revision:
          Snapshot.interval(snapshot, :speech_to_text, state.identity.participant_id)
    }
  end

  defp demanded?(state, snapshot) do
    SpeechToTextDemand.required?(snapshot, state.identity.participant_id)
  end

  defp supported_audio?(state, frame) do
    frame.tenant_id == state.identity.tenant_id and
      frame.room_id == state.identity.room_id and
      frame.incarnation_id == state.identity.incarnation_id and
      frame.participant_id == state.identity.participant_id and
      frame.connection_id == state.identity.connection_id and
      frame.codec == state.media_format.codec and
      frame.sample_rate == state.media_format.sample_rate and
      frame.channels in [1, 2] and
      is_binary(frame.payload) and byte_size(frame.payload) > 0 and
      byte_size(frame.payload) <= @maximum_audio_bytes
  end

  defp start_transport(module, connection, transport_options) do
    module.start_link(
      owner: self(),
      connection: connection,
      transport_options: transport_options
    )
  end

  defp safe_send_audio(module, transport, audio) do
    try do
      module.send_audio(transport, audio)
    catch
      :exit, _reason -> {:error, :transport_closed}
    end
  end

  defp safe_close(module, transport) do
    try do
      module.close(transport)
    catch
      :exit, _reason -> :ok
    end
  end
end
