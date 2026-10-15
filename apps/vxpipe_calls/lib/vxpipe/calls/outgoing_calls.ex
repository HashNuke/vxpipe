defmodule Vxpipe.Calls.OutgoingCalls do
  @moduledoc "Outgoing-call compatibility entry point and durable lifecycle projections."

  alias Vxpipe.Calls.{CallClaims, PreparedCall, Repositories}

  defdelegate claim(
                principal,
                call_spec_id,
                initial_variables,
                to,
                idempotency_key,
                options \\ []
              ), to: CallClaims, as: :claim_outgoing

  def mark_started(call, incarnation_id, started_at, options \\ [])

  def mark_started(
        %PreparedCall{plan: %{direction: :outgoing}} = call,
        incarnation,
        %DateTime{} = started,
        options
      )
      when is_binary(incarnation) and byte_size(incarnation) > 0 do
    with {:ok, repository} <- Repositories.fetch(options, :call_repository),
         do:
           Repositories.call(repository, :mark_outgoing_call_started, [call, incarnation, started])
  end

  def mark_started(_call, _incarnation, _started, _options), do: {:error, :invalid_outgoing_start}

  def mark_failed(call, reason, options \\ [])

  def mark_failed(%PreparedCall{plan: %{direction: :outgoing}} = call, reason, options)
      when reason in [:room_start_failed, :session_start_failed, :startup_unknown] do
    with {:ok, repository} <- Repositories.fetch(options, :call_repository) do
      now = Keyword.get_lazy(options, :now, &DateTime.utc_now/0)
      Repositories.call(repository, :mark_outgoing_call_failed, [call, reason, now])
    end
  end

  def mark_failed(_call, _reason, _options), do: {:error, :invalid_outgoing_failure}
end
