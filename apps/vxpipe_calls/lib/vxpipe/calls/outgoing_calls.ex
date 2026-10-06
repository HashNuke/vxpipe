defmodule Vxpipe.Calls.OutgoingCalls do
  @moduledoc "Durable, tenant-scoped admission for published outgoing call specifications."

  alias Vxpipe.Calls.{
    CanonicalJSON,
    CallSpecCredentials,
    PreparedCallFactory,
    PreparedCall,
    Principal,
    Repositories
  }

  def claim(principal, call_spec_id, initial_variables, idempotency_key, options \\ [])

  def claim(%Principal{} = principal, call_spec_id, initial_variables, key, options)
      when is_binary(call_spec_id) and is_map(initial_variables) and is_list(options) do
    with :ok <- authorize(principal),
         :ok <- valid_key(key),
         {:ok, repository} <- Repositories.fetch(options, :call_repository),
         {:ok, digest} <- digest(call_spec_id, initial_variables, key) do
      case existing(repository, principal.tenant_key, key, digest) do
        :new ->
          prepare(principal, call_spec_id, initial_variables, key, digest, repository, options)

        result ->
          result
      end
    end
  end

  def claim(_principal, _call_spec_id, _variables, _key, _options),
    do: {:error, :invalid_outgoing_call}

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

  defp prepare(principal, call_spec_id, variables, key, digest, repository, options) do
    with {:ok, specifications} <- Repositories.fetch(options, :call_spec_repository),
         {:ok, revision} <-
           Repositories.call(specifications, :fetch_published_revision, [
             principal.tenant_key,
             call_spec_id
           ]),
         :ok <- outgoing_revision(revision),
         {:ok, call} <- PreparedCallFactory.build(revision, variables, :telephony, options) do
      call = %{call | state: :admitting, idempotency_key: key, idempotency_digest: digest}

      authorize = fn ->
        CallSpecCredentials.with_active(revision, call.plan, options, fn -> {:ok, :authorized} end)
      end

      Repositories.call(repository, :claim_outgoing_call, [call, authorize])
    end
  end

  defp existing(_repository, _tenant, nil, _digest), do: :new

  defp existing(repository, tenant, key, digest) do
    case Repositories.call(repository, :fetch_outgoing_by_key, [tenant, key]) do
      {:ok, %{idempotency_digest: ^digest} = call} -> {:duplicate, call}
      {:ok, _call} -> {:error, :idempotency_conflict}
      {:error, :not_found} -> :new
      {:error, _reason} = error -> error
    end
  end

  defp outgoing_revision(%{compiled_metadata: %{"direction" => "outgoing"}}), do: :ok
  defp outgoing_revision(_revision), do: {:error, :call_spec_not_outgoing}

  defp authorize(%Principal{scopes: scopes}) do
    if MapSet.member?(scopes, :calls), do: :ok, else: {:error, :not_authorized}
  end

  defp valid_key(nil), do: :ok

  defp valid_key(key) when is_binary(key) and byte_size(key) in 1..256 do
    if String.valid?(key) and String.trim(key) != "",
      do: :ok,
      else: {:error, :invalid_idempotency_key}
  end

  defp valid_key(_key), do: {:error, :invalid_idempotency_key}

  defp digest(_id, _variables, nil), do: {:ok, nil}

  defp digest(id, variables, _key) do
    value = CanonicalJSON.encode!(%{"call_spec_id" => id, "initial_variables" => variables})
    {:ok, :crypto.hash(:sha256, value)}
  rescue
    _error -> {:error, :invalid_outgoing_call}
  end
end
