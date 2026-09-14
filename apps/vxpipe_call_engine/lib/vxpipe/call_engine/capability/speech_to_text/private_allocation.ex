defmodule Vxpipe.CallEngine.Capability.SpeechToText.PrivateAllocation do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot

  @enforce_keys [:owner, :attempt_id, :deadline_ms, :monitor, :timer, :token]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          owner: pid(),
          attempt_id: String.t(),
          deadline_ms: integer(),
          monitor: reference(),
          timer: reference(),
          token: reference()
        }

  def new(options, participant_id) do
    case Keyword.fetch(options, :preparation) do
      :error ->
        {:ok, nil}

      {:ok, preparation} ->
        allocate(preparation, Keyword.get(options, :initial_policy), participant_id)
    end
  end

  def validate_preparation(nil, _options), do: :ok

  def validate_preparation(%__MODULE__{} = allocation, options) do
    if active?(allocation) and allocation.owner == Keyword.get(options, :owner) and
         allocation.attempt_id == Keyword.get(options, :attempt_id) and
         allocation.deadline_ms == Keyword.get(options, :deadline_ms),
       do: :ok,
       else: {:error, :invalid_preparation}
  end

  def validate_policy(nil, _snapshot, _pending, _participant_id), do: :ok

  def validate_policy(%__MODULE__{} = allocation, snapshot, pending, participant_id) do
    cond do
      not Snapshot.valid?(snapshot) ->
        {:error, :invalid_policy}

      not active?(allocation) ->
        {:error, :policy_not_ready}

      not MapSet.member?(snapshot.present_participant_ids, participant_id) ->
        :ok

      pending != nil and pending.change == :replace and pending.candidate.snapshot == snapshot ->
        :ok

      true ->
        {:error, :policy_not_prepared}
    end
  end

  def release(nil), do: :ok

  def release(%__MODULE__{} = allocation) do
    Process.demonitor(allocation.monitor, [:flush])
    Process.cancel_timer(allocation.timer)
    :ok
  end

  defp allocate(options, snapshot, participant_id) when is_list(options) do
    with true <- Keyword.keyword?(options),
         owner when is_pid(owner) <- Keyword.get(options, :owner),
         attempt when is_binary(attempt) and byte_size(attempt) in 1..128 <-
           Keyword.get(options, :attempt_id),
         deadline when is_integer(deadline) <- Keyword.get(options, :deadline_ms),
         true <- deadline > now() and Process.alive?(owner),
         true <- Snapshot.valid?(snapshot),
         false <- MapSet.member?(snapshot.present_participant_ids, participant_id) do
      token = make_ref()

      {:ok,
       %__MODULE__{
         owner: owner,
         attempt_id: attempt,
         deadline_ms: deadline,
         monitor: Process.monitor(owner),
         timer:
           Process.send_after(self(), {:private_speech_expired, token}, max(deadline - now(), 0)),
         token: token
       }}
    else
      _invalid -> {:error, :invalid_preparation}
    end
  end

  defp allocate(_options, _snapshot, _participant_id), do: {:error, :invalid_preparation}

  defp active?(allocation),
    do: now() < allocation.deadline_ms and Process.alive?(allocation.owner)

  defp now, do: System.monotonic_time(:millisecond)
end
