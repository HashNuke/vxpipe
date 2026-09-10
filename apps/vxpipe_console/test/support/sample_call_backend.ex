defmodule Vxpipe.Console.TestSampleCallBackend do
  use Agent

  @behaviour Vxpipe.Console.SampleCallBackend

  alias Vxpipe.Calls.{DefinitionRevision, IssuedApiKey, IssuedJoinToken, ParticipantRoute}
  alias Vxpipe.Calls.{Principal, Tenant}

  @api_key "vxp_test-only-sample-backend-key"
  @tenant_key "BBBBBBBBBBBBBBBB"
  @definition_id "10000000-0000-4000-8000-000000000001"
  @participant_key "20000000-0000-4000-8000-000000000002"
  @call_id "30000000-0000-4000-8000-000000000003"

  def start_link(options) do
    Agent.start_link(fn ->
      %{
        bootstrap_exception?: Keyword.get(options, :bootstrap_exception?, false),
        initial_variables: Keyword.fetch!(options, :initial_variables),
        observer: Keyword.fetch!(options, :observer),
        operations: []
      }
    end)
  end

  def backend(agent), do: {__MODULE__, agent}
  def operations(agent), do: Agent.get(agent, &Enum.reverse(&1.operations))

  def bootstrap(agent, name) do
    operation(agent, {:bootstrap, name})
    state = Agent.get(agent, & &1)

    if state.bootstrap_exception? do
      raise "synthetic backend exception"
    end

    inserted_at = ~U[2026-09-09 13:00:00.000000Z]

    {:ok, %Tenant{key: @tenant_key, name: name, inserted_at: inserted_at},
     %IssuedApiKey{
       id: "40000000-0000-4000-8000-000000000004",
       tenant_key: @tenant_key,
       name: "bootstrap",
       scopes: MapSet.new([:calls]),
       secret: @api_key,
       inserted_at: inserted_at
     }}
  end

  def save_definition(agent, tenant_key, definition) do
    operation(agent, {:save_definition, tenant_key, definition})
    {:ok, revision(definition, [])}
  end

  def publish_definition(agent, tenant_key, definition_id, revision) do
    operation(agent, {:publish_definition, tenant_key, definition_id, revision})

    route = %ParticipantRoute{
      key: @participant_key,
      tenant_key: @tenant_key,
      definition_id: @definition_id,
      definition_revision: 1,
      participant_ref: "caller",
      published_at: ~U[2026-09-09 13:00:01.000000Z]
    }

    {:ok, %{revision(%{}, [route]) | published_at: route.published_at}}
  end

  def authenticate(agent, tenant_key, secret) do
    operation(agent, {:authenticate, tenant_key, secret})

    if tenant_key == @tenant_key and secret == @api_key do
      {:ok,
       %Principal{
         tenant_key: tenant_key,
         api_key_id: "40000000-0000-4000-8000-000000000004",
         scopes: MapSet.new([:calls])
       }}
    else
      {:error, :invalid_api_key}
    end
  end

  def prepare_call(agent, principal, participant_key, initial_variables) do
    operation(agent, {:prepare_call, principal.tenant_key, participant_key, initial_variables})
    state = Agent.get(agent, & &1)

    if initial_variables == state.initial_variables do
      token = %IssuedJoinToken{
        id: "50000000-0000-4000-8000-000000000005",
        secret: "vxj_test-only-sample-join-token",
        tenant_key: @tenant_key,
        call_id: @call_id,
        participant_key: @participant_key,
        participant_ref: "caller",
        issued_at: ~U[2026-09-09 13:00:02.000000Z],
        expires_at: ~U[2026-09-09 13:05:02.000000Z]
      }

      send(state.observer, {:sample_call_prepared, token.call_id})
      {:ok, %{id: token.call_id}, token}
    else
      {:error, :unexpected_variables}
    end
  end

  def api_key, do: @api_key
  def call_id, do: @call_id
  def participant_key, do: @participant_key
  def tenant_key, do: @tenant_key

  defp revision(source, routes) do
    %DefinitionRevision{
      tenant_key: @tenant_key,
      definition_id: @definition_id,
      revision: 1,
      schema_version: "20260910.01",
      source: source,
      source_digest: "test-digest",
      compiled_metadata: %{"entry_caller" => "caller"},
      validation_errors: [],
      routes: routes,
      published_at: nil,
      inserted_at: ~U[2026-09-09 13:00:00.000000Z]
    }
  end

  defp operation(agent, value) do
    Agent.update(agent, fn state -> %{state | operations: [value | state.operations]} end)
  end
end
