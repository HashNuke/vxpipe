defmodule Vxpipe.Calls.PublicationFinalizer do
  @moduledoc "Short-lived process that assesses an ended call until its details can be published."

  use GenServer

  alias Vxpipe.Calls.{CallDetailsFinalization, PublicationFinalizerJob}
  alias Vxpipe.Calls.PublicationFinalizer.State

  @spec start_link(PublicationFinalizerJob.t()) :: GenServer.on_start()
  def start_link(%PublicationFinalizerJob{} = job) do
    GenServer.start_link(__MODULE__, job, name: PublicationFinalizerJob.via(job))
  end

  @spec child_spec(PublicationFinalizerJob.t()) :: Supervisor.child_spec()
  def child_spec(%PublicationFinalizerJob{} = job) do
    %{
      id: {__MODULE__, PublicationFinalizerJob.key(job)},
      start: {__MODULE__, :start_link, [job]},
      restart: :transient,
      shutdown: 5_000
    }
  end

  @impl true
  def init(%PublicationFinalizerJob{} = job),
    do: {:ok, %State{job: job}, {:continue, :assess}}

  @impl true
  def handle_continue(:assess, state), do: assess(state)

  @impl true
  def handle_info(
        {:vxpipe_publication_timer, token},
        %State{timer_token: token} = state
      ) do
    assess(%{state | timer: nil, timer_token: nil})
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %State{timer: nil}), do: :ok

  def terminate(_reason, state) do
    {timer, context} = state.job.timer
    timer.cancel(state.timer, context)
  end

  defp assess(state) do
    {clock, context} = state.job.clock
    assessed_at = clock.now(context)

    case CallDetailsFinalization.assess(
           state.job.tenant_key,
           state.job.call_id,
           assessed_at,
           state.job.options
         ) do
      {:wait, decision} ->
        {:noreply, schedule(state, wait_ms(state, decision.deadline, assessed_at))}

      {:publish, decision, _snapshot, worker, disposition} ->
        notify(
          state,
          {:vxpipe_call_details_finalization_submitted, self(), worker, disposition,
           decision.completeness}
        )

        {:stop, :normal, state}

      {:error, reason} when reason in [:call_not_found, :call_not_ended] ->
        notify(state, {:vxpipe_call_details_finalization_skipped, self(), reason})
        {:stop, :normal, state}

      {:error, reason} ->
        notify(state, {:vxpipe_call_details_finalization_retrying, self(), reason})
        {:noreply, schedule(state, state.job.settlement_poll_ms)}
    end
  end

  defp wait_ms(state, deadline, assessed_at) do
    remaining_ms = max(DateTime.diff(deadline, assessed_at, :millisecond), 0)
    min(state.job.settlement_poll_ms, remaining_ms)
  end

  defp schedule(%State{timer: nil} = state, delay_ms) do
    token = make_ref()
    {timer, context} = state.job.timer
    handle = timer.schedule(self(), token, delay_ms, context)
    %{state | timer: handle, timer_token: token}
  end

  defp notify(%State{job: %PublicationFinalizerJob{observer: nil}}, _message), do: :ok

  defp notify(%State{job: %PublicationFinalizerJob{observer: observer}}, message),
    do: send(observer, message)
end
