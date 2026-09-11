defmodule Vxpipe.CallEngine.RoomMixer.Playout do
  @moduledoc false

  @enforce_keys [
    :clock,
    :clock_origin_ms,
    :delay_ms,
    :frame_duration_ms,
    :frame_samples,
    :sample_rate,
    :schedule,
    :tick_ref
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          clock: (-> integer()),
          clock_origin_ms: integer(),
          delay_ms: non_neg_integer(),
          frame_duration_ms: pos_integer(),
          frame_samples: pos_integer(),
          sample_rate: pos_integer(),
          schedule: (pid(), term(), non_neg_integer() -> reference()),
          tick_ref: reference() | nil
        }

  @spec new(keyword(), integer(), map()) :: {:ok, nil | t()} | {:error, term()}
  def new(options, clock_origin_ms, format) do
    case Keyword.get(options, :playout_delay_ms) do
      nil ->
        {:ok, nil}

      delay_ms when is_integer(delay_ms) and delay_ms >= 0 ->
        with clock when is_function(clock, 0) <-
               Keyword.get(options, :clock, fn -> System.monotonic_time(:millisecond) end),
             schedule when is_function(schedule, 3) <-
               Keyword.get(options, :schedule, &Process.send_after/3) do
          {:ok,
           %__MODULE__{
             clock: clock,
             clock_origin_ms: clock_origin_ms,
             delay_ms: delay_ms,
             frame_duration_ms: frame_duration_ms(format),
             frame_samples: format.frame_samples,
             sample_rate: format.sample_rate,
             schedule: schedule,
             tick_ref: nil
           }}
        else
          _invalid -> {:error, {:invalid_room_mixer_option, :playout_clock}}
        end

      _invalid ->
        {:error, {:invalid_room_mixer_option, :playout_delay_ms}}
    end
  end

  @spec arm(nil | t(), pid()) :: nil | t()
  def arm(nil, _target), do: nil

  def arm(%__MODULE__{} = playout, target) when is_pid(target) do
    tick_ref = make_ref()

    _timer =
      playout.schedule.(target, {:vxpipe_room_mixer_tick, tick_ref}, playout.frame_duration_ms)

    %{playout | tick_ref: tick_ref}
  end

  @spec due_timestamp(t(), integer()) :: :not_due | {:ok, non_neg_integer()}
  def due_timestamp(%__MODULE__{} = playout, last_flushed_timestamp) do
    elapsed_ms = playout.clock.() - playout.clock_origin_ms

    if elapsed_ms < playout.delay_ms do
      :not_due
    else
      elapsed_samples = div((elapsed_ms - playout.delay_ms) * playout.sample_rate, 1_000)
      timestamp = div(elapsed_samples, playout.frame_samples) * playout.frame_samples

      if timestamp > last_flushed_timestamp, do: {:ok, timestamp}, else: :not_due
    end
  end

  defp frame_duration_ms(format) do
    max(div(format.frame_samples * 1_000 + format.sample_rate - 1, format.sample_rate), 1)
  end
end
