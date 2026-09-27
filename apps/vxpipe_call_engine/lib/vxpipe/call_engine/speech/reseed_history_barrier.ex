defmodule Vxpipe.CallEngine.Speech.ReseedHistoryBarrier do
  @moduledoc "Orders provider reseed after room-published history reaches its consumer."

  def request(channel) do
    reference = make_ref()
    GenServer.cast(channel, {:reseed_history_barrier, self(), reference})
    reference
  end

  def forward(
        %{
          producer: producer,
          consumer: consumer,
          descriptor: %{kind: :sts, continuity: :history_reseed}
        },
        producer,
        reference,
        channel
      )
      when is_pid(consumer) and is_reference(reference) do
    send(consumer, {:vxpipe_sts_reseed_history_barrier, channel, producer, reference})
  end

  def forward(_state, _producer, _reference, _channel), do: :ok
end
