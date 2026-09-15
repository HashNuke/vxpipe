defmodule Vxpipe.Console.SampleCallBackend do
  @moduledoc false

  alias Vxpipe.Calls

  @callback issue_api_key(term(), String.t()) :: {:ok, struct()} | {:error, term()}
  @callback save_definition(term(), String.t(), map()) :: {:ok, struct()} | {:error, term()}
  @callback publish_definition(term(), String.t(), String.t(), pos_integer()) ::
              {:ok, struct()} | {:error, term()}
  @callback authenticate(term(), String.t(), String.t()) :: {:ok, struct()} | {:error, term()}
  @callback prepare_call(term(), struct(), String.t(), map()) ::
              {:ok, struct(), struct()} | {:error, term()}
  @callback issue_join_token(term(), struct(), String.t(), String.t()) ::
              {:ok, struct()} | {:error, term()}

  def issue_api_key(options, tenant_key),
    do: Calls.issue_api_key(tenant_key, "development-sample", [:calls], options)

  def save_definition(options, tenant_key, definition),
    do: Calls.save_definition(tenant_key, definition, options)

  def publish_definition(options, tenant_key, definition_id, revision),
    do: Calls.publish_definition(tenant_key, definition_id, revision, options)

  def authenticate(options, tenant_key, secret),
    do: Calls.authenticate(tenant_key, secret, :calls, options)

  def prepare_call(options, principal, participant_key, initial_variables),
    do: Calls.prepare_call(principal, participant_key, initial_variables, options)

  def issue_join_token(options, principal, call_id, participant_key),
    do: Calls.issue_join_token(principal, call_id, participant_key, options)
end
