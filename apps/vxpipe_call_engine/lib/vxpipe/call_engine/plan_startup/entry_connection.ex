defmodule Vxpipe.CallEngine.PlanStartup.EntryConnection do
  @moduledoc false

  alias Vxpipe.CallEngine.{Error, ResolvedCallPlan}
  alias Vxpipe.CallEngine.CallSpec.ConnectionIntent

  def caller(%{direction: :outgoing}, %ResolvedCallPlan.Participant{
        connection: %ConnectionIntent{service: service, mode: :dial, admission: :start_call}
      })
      when is_binary(service), do: :ok

  def caller(%{direction: :outgoing}, caller) do
    unsupported(
      ["participants", caller.call_spec_key, "connection"],
      "must be a supported phone dial/start_call connection intent"
    )
  end

  def caller(_plan, caller), do: receive_connection(caller)

  def transport(%ResolvedCallPlan{transport: :web}), do: :ok
  def transport(%ResolvedCallPlan{transport: :telephony}), do: :ok

  def transport(_plan) do
    unsupported(["transport", "type"], "must be a supported transport")
  end

  def receive_connection(%ResolvedCallPlan.Participant{
        connection: %ConnectionIntent{service: :web, mode: :receive, admission: :start_call}
      }),
      do: :ok

  def receive_connection(%ResolvedCallPlan.Participant{
        connection: %ConnectionIntent{
          service: service,
          mode: :receive,
          admission: :start_call
        }
      })
      when is_binary(service),
      do: :ok

  def receive_connection(caller) do
    unsupported(
      ["participants", caller.call_spec_key, "connection"],
      "must be a supported receive/start_call connection intent"
    )
  end

  defp unsupported(path, reason) do
    {:error,
     Error.new(:unsupported_call_plan, "The resolved call plan is not supported by this runtime.",
       details: %{"path" => path, "reason" => reason}
     )}
  end
end
