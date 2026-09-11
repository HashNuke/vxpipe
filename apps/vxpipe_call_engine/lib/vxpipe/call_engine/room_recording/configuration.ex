defmodule Vxpipe.CallEngine.RoomRecording.Configuration do
  @moduledoc false

  alias Vxpipe.CallEngine.Recording.Writer

  @enforce_keys [
    :identity,
    :mixer,
    :recording_token,
    :maximum_pull_frames,
    :writer,
    :writer_options,
    :targets
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          identity: %{
            tenant_id: String.t(),
            call_id: String.t(),
            room_id: String.t(),
            incarnation_id: String.t()
          },
          mixer: pid(),
          recording_token: reference(),
          maximum_pull_frames: pos_integer(),
          writer: module(),
          writer_options: keyword(),
          targets: [target()]
        }

  @type target :: :full_mix | {:individual_tracks, [String.t()]}

  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(options) when is_list(options) do
    with {:ok, identity} <- identity(options),
         {:ok, mixer} <- mixer(options),
         recording_token when is_reference(recording_token) <-
           Keyword.get(options, :recording_token),
         {:ok, maximum_pull_frames} <- positive(options, :maximum_pull_frames),
         {:ok, writer, writer_options} <- writer(options),
         {:ok, targets} <- targets(options) do
      {:ok,
       %__MODULE__{
         identity: identity,
         mixer: mixer,
         recording_token: recording_token,
         maximum_pull_frames: maximum_pull_frames,
         writer: writer,
         writer_options: writer_options,
         targets: targets
       }}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_room_recording_options}
    end
  end

  def new(_options), do: {:error, :invalid_room_recording_options}

  defp mixer(options) do
    try do
      case options |> Keyword.get(:mixer) |> GenServer.whereis() do
        mixer when is_pid(mixer) -> {:ok, mixer}
        nil -> {:error, :room_mixer_unavailable}
      end
    catch
      _kind, _reason -> {:error, :invalid_room_recording_options}
    end
  end

  defp identity(options) do
    identity = %{
      tenant_id: Keyword.get(options, :tenant_id),
      call_id: Keyword.get(options, :call_id),
      room_id: Keyword.get(options, :room_id),
      incarnation_id: Keyword.get(options, :incarnation_id)
    }

    if Enum.all?(Map.values(identity), &valid_identifier?/1),
      do: {:ok, identity},
      else: {:error, :invalid_room_recording_identity}
  end

  defp writer(options) do
    case Keyword.get(options, :writer) do
      {writer, writer_options} when is_atom(writer) and is_list(writer_options) ->
        if Writer.valid?(writer),
          do: {:ok, writer, writer_options},
          else: {:error, :invalid_recording_writer}

      _invalid ->
        {:error, :invalid_recording_writer}
    end
  end

  defp targets(options) do
    case Keyword.get(options, :targets) do
      targets when is_list(targets) and targets != [] ->
        normalize_targets(targets)

      _invalid ->
        {:error, :invalid_recording_targets}
    end
  end

  defp normalize_targets(targets) do
    with {:ok, targets} <- reduce_targets(targets),
         true <- length(targets) == length(Enum.uniq(targets)),
         true <- Enum.count(targets, &individual_target?/1) <= 1 do
      {:ok, targets}
    else
      _invalid -> {:error, :invalid_recording_targets}
    end
  end

  defp reduce_targets(targets) do
    Enum.reduce_while(targets, {:ok, []}, fn target, {:ok, normalized} ->
      case normalize_target(target) do
        {:ok, target} -> {:cont, {:ok, normalized ++ [target]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp normalize_target(:full_mix), do: {:ok, :full_mix}

  defp normalize_target({:individual_tracks, participant_ids}) when is_list(participant_ids) do
    if participant_ids != [] and Enum.all?(participant_ids, &valid_identifier?/1) and
         length(participant_ids) == length(Enum.uniq(participant_ids)),
       do: {:ok, {:individual_tracks, participant_ids}},
       else: :error
  end

  defp normalize_target(_target), do: :error

  defp individual_target?({:individual_tracks, _participant_ids}), do: true
  defp individual_target?(_target), do: false

  defp positive(options, key) do
    case Keyword.get(options, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _invalid -> {:error, {:invalid_room_recording_option, key}}
    end
  end

  defp valid_identifier?(value),
    do: is_binary(value) and value != "" and byte_size(value) <= 128
end
