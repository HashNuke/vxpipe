defmodule Vxpipe.CallEngine.RoomSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom, JoinParticipant, SendText}

  alias Vxpipe.CallEngine.{
    Error,
    Id,
    RoomAuthority,
    RoomCapabilitySupervisor,
    RoomIncarnationSupervisor
  }

  def start_link(_options) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  def create_room(%CreateRoom{} = command) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {command.tenant_id, command.room_id}) do
      [] -> start_room(command)
      [_room] -> {:error, room_already_exists(command.room_id)}
    end
  end

  def join_participant(%JoinParticipant{} = command) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {command.tenant_id, command.room_id}) do
      [{room_authority, _value}] -> RoomAuthority.join_participant(room_authority, command)
      [] -> {:error, room_not_found(command.room_id)}
    end
  end

  def attach_connection(%AttachConnection{} = command, speech_to_text_options, output_sink) do
    case lookup_room(command.tenant_id, command.room_id) do
      {:ok, room_authority} ->
        case RoomAuthority.attach_connection(room_authority, command, self(), output_sink) do
          {:ok, role} ->
            start_connection_speech_to_text(
              room_authority,
              command,
              role,
              speech_to_text_options
            )

          {:error, %Error{} = error} ->
            {:error, error}
        end

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp start_connection_speech_to_text(room_authority, command, :human, options) do
    if Keyword.fetch!(options, :enabled) do
      provider_module = Keyword.fetch!(options, :provider)

      with {:ok, provider_config} <-
             provider_module.new(Keyword.fetch!(options, :provider_options)),
           {:ok, capability, ingress} <-
             RoomCapabilitySupervisor.start_speech_to_text(
               command.incarnation_id,
               room_authority,
               command,
               {provider_module, provider_config},
               Keyword.fetch!(options, :transport),
               Keyword.fetch!(options, :media_ingress)
             ) do
        bind_connection_speech_to_text(
          room_authority,
          command,
          capability,
          ingress
        )
      else
        _error -> attachment_speech_to_text_failed(room_authority, command)
      end
    else
      {:ok, room_authority, nil}
    end
  end

  defp start_connection_speech_to_text(room_authority, _command, _role, _options) do
    {:ok, room_authority, nil}
  end

  defp bind_connection_speech_to_text(room_authority, command, capability, ingress) do
    case RoomAuthority.bind_speech_to_text(
           room_authority,
           command,
           self(),
           capability,
           ingress
         ) do
      :ok ->
        {:ok, room_authority, ingress}

      {:error, _reason} ->
        :ok =
          RoomCapabilitySupervisor.stop_speech_to_text(
            command.incarnation_id,
            capability,
            ingress
          )

        attachment_speech_to_text_failed(room_authority, command)
    end
  end

  defp attachment_speech_to_text_failed(room_authority, command) do
    :ok = RoomAuthority.detach_connection(room_authority, command, self())

    {:error,
     Error.new(
       :speech_to_text_unavailable,
       "The speech-to-text capability could not be started.",
       retryable: true
     )}
  end

  def send_text(%SendText{} = command) do
    case lookup_room(command.tenant_id, command.room_id) do
      {:ok, room_authority} -> RoomAuthority.send_text(room_authority, command)
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp start_room(command) do
    incarnation_id = Id.generate(:room_incarnation)
    options = [command: command, incarnation_id: incarnation_id]

    case DynamicSupervisor.start_child(__MODULE__, {RoomIncarnationSupervisor, options}) do
      {:ok, _supervisor} ->
        {:ok, RoomAuthority.snapshot(command.tenant_id, command.room_id)}

      {:error, {:shutdown, {:failed_to_start_child, RoomAuthority, {:already_started, _pid}}}} ->
        {:error, room_already_exists(command.room_id)}

      {:error, _reason} ->
        {:error,
         Error.new(
           :room_start_failed,
           "The room incarnation could not be started.",
           retryable: true
         )}
    end
  end

  defp lookup_room(tenant_id, room_id) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {tenant_id, room_id}) do
      [{room_authority, _value}] -> {:ok, room_authority}
      [] -> {:error, room_not_found(room_id)}
    end
  end

  defp room_already_exists(room_id) do
    Error.new(
      :room_already_exists,
      "The room already exists.",
      details: %{"room_id" => room_id}
    )
  end

  defp room_not_found(room_id) do
    Error.new(
      :room_not_found,
      "The room does not exist.",
      details: %{"room_id" => room_id}
    )
  end
end
