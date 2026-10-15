defmodule Vxpipe.Gateway.CallCreation do
  @moduledoc "Creates a published-spec call and starts only a newly claimed outgoing call."

  alias Vxpipe.Calls
  alias Vxpipe.Gateway.OutgoingCallAdmission

  def authenticate(options, secret), do: Calls.authenticate_api_key(secret, options)

  def create(options, actor, tenant, specification, variables, to, key) do
    case Calls.claim_call(actor, tenant, specification, variables, to, key, options) do
      {:ok, %{state: :prepared} = call} ->
        {:ok, :created, call}

      {:ok, %{state: :admitting, plan: %{direction: :outgoing}} = call} ->
        with {:ok, started} <- OutgoingCallAdmission.start(options, call),
             do: {:ok, :created, started}

      {:duplicate,
       %{state: :failed, terminal_reason: :startup_unknown, plan: %{direction: :outgoing}}} ->
        {:error, :outgoing_submission_unknown}

      {:duplicate, %{state: :failed, plan: %{direction: :outgoing}}} ->
        {:error, :outgoing_call_start_failed}

      {:duplicate, call} ->
        {:ok, :replayed, call}

      {:error, _reason} = error ->
        error

      _invalid ->
        {:error, :call_management_unavailable}
    end
  end
end
