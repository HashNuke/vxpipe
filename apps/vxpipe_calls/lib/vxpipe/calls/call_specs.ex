defmodule Vxpipe.Calls.CallSpecs do
  @moduledoc """
  Trusted host call-spec revision and participant-route workflows.

  External authors must enter through `Vxpipe.Calls.CallSpecAuthoring`, which
  establishes the writing principal's service permissions before delegating here.
  A tenant key argument by itself is a resource locator, not authentication.
  """

  alias Vxpipe.CallEngine.{CallSpec, CallInvocation, Error}
  alias Vxpipe.CallEngine.CallSpec.OpeningAudio

  alias Vxpipe.Calls.{
    CallPlanCompiler,
    CallSpecCredentials,
    CallSpecGuardrailIds,
    CallSpecRevision,
    ParticipantRoute,
    PrivateMaterial,
    PublicId,
    Repositories,
    TelephonyRoute
  }

  @maximum_attempts 4

  @spec save(String.t(), map(), keyword()) :: {:ok, CallSpecRevision.t()} | {:error, term()}
  def save(tenant_key, source, options \\ [])

  def save(tenant_key, source, options) when is_map(source) do
    with :ok <- public_source(source),
         {:ok, credential_repository} <- Repositories.fetch(options, :credential_repository),
         {:ok, _tenant} <-
           Repositories.call(credential_repository, :fetch_tenant, [tenant_key]),
         {:ok, call_spec_repository} <-
           Repositories.fetch(options, :call_spec_repository),
         {:ok, source} <- json_safe(source),
         {:ok, call_spec_id} <- call_spec_id(call_spec_repository, options),
         {:ok, next} <-
           Repositories.call(call_spec_repository, :next_revision, [tenant_key, call_spec_id]),
         {:ok, source, guardrail_known} <-
           assign_guardrail_ids(
             call_spec_repository,
             tenant_key,
             call_spec_id,
             next,
             source,
             options
           ) do
      attempt_save(
        call_spec_repository,
        tenant_key,
        call_spec_id,
        next,
        source,
        guardrail_known,
        options,
        @maximum_attempts
      )
    else
      {:error, :not_found} -> {:error, :tenant_not_found}
      {:error, _reason} = error -> error
    end
  end

  def save(_tenant_key, _source, _options), do: {:error, :invalid_call_spec_source}

  @spec fetch(String.t(), String.t(), pos_integer(), keyword()) ::
          {:ok, CallSpecRevision.t()} | {:error, term()}
  def fetch(tenant_key, call_spec_id, revision, options \\ []) do
    with {:ok, repository} <- Repositories.fetch(options, :call_spec_repository),
         {:ok, stored} <-
           Repositories.call(repository, :fetch_revision, [tenant_key, call_spec_id, revision]) do
      {:ok, with_current_warnings(stored, options)}
    end
  end

  @spec publish(String.t(), String.t(), pos_integer(), keyword()) ::
          {:ok, CallSpecRevision.t()} | {:error, term()}
  def publish(tenant_key, call_spec_id, revision, options \\ []) do
    with {:ok, repository} <- Repositories.fetch(options, :call_spec_repository),
         {:ok, stored} <-
           Repositories.call(repository, :fetch_revision, [tenant_key, call_spec_id, revision]),
         :ok <- publishable(stored),
         {:ok, call_spec} <-
           CallSpec.new(stored.source, resource_id: call_spec_id, revision: revision) do
      warnings = recording_warnings(call_spec, options)

      with {:ok, published} <-
             CallSpecCredentials.with_active(
               call_spec,
               tenant_key,
               Keyword.merge(options,
                 outbound_number_required?: true,
                 telephony_publication?: true
               ),
               fn ->
                 Repositories.call(repository, :publish_revision, [
                   tenant_key,
                   call_spec_id,
                   revision,
                   now(options)
                 ])
               end
             ) do
        {:ok, %{published | validation_warnings: warnings}}
      end
    end
  end

  @spec resolve_route(String.t(), String.t(), keyword()) ::
          {:ok, ParticipantRoute.t()} | {:error, term()}
  def resolve_route(tenant_key, route_key, options \\ []) do
    with {:ok, repository} <- Repositories.fetch(options, :call_spec_repository) do
      Repositories.call(repository, :resolve_route, [tenant_key, route_key])
    end
  end

  @spec resolve_telephony_route(
          {:tenant, String.t()},
          String.t(),
          String.t(),
          keyword()
        ) :: {:ok, TelephonyRoute.t()} | {:error, term()}
  def resolve_telephony_route(scope, service, number, options \\ []) do
    with :ok <- telephony_scope(scope),
         true <- is_binary(service) and byte_size(service) > 0,
         true <- is_binary(number) and byte_size(number) > 0,
         {:ok, repository} <- Repositories.fetch(options, :call_spec_repository) do
      Repositories.call(repository, :resolve_telephony_route, [scope, service, number])
    else
      false -> {:error, :invalid_telephony_route}
      {:error, _reason} = error -> error
    end
  end

  defp call_spec_id(repository, options) do
    case Keyword.fetch(options, :call_spec_id) do
      {:ok, id} -> {:ok, id}
      :error -> Repositories.call(repository, :allocate_id, [])
    end
  end

  defp assign_guardrail_ids(repository, tenant_key, call_spec_id, next, source, options) do
    if CallSpecGuardrailIds.supported?(source) and
         CallSpecGuardrailIds.has_guardrail_questions?(source) do
      id_generator =
        Keyword.get(options, :guardrail_id_generator, &CallSpecGuardrailIds.default_id/0)

      predecessor = if Keyword.has_key?(options, :call_spec_id), do: next, else: 1

      with {:ok, known} <-
             fetch_known_guardrail_ids(repository, tenant_key, call_spec_id, predecessor),
           {:ok, assigned} <- assign_questions(source, known, id_generator) do
        {:ok, assigned, known}
      end
    else
      {:ok, source, %{}}
    end
  end

  defp assign_questions(source, known, generator) when map_size(known) == 0,
    do: CallSpecGuardrailIds.assign_new(source, generator)

  defp assign_questions(source, known, generator),
    do: CallSpecGuardrailIds.assign_update(source, known, generator)

  # Recheck caller-owned references against the winner without reallocating new IDs.
  defp verify_retry_guardrails(repository, tenant_key, call_spec_id, next, source, known) do
    if CallSpecGuardrailIds.supported?(source) and
         CallSpecGuardrailIds.has_guardrail_questions?(source) do
      with {:ok, winning} <- fetch_known_guardrail_ids(repository, tenant_key, call_spec_id, next) do
        CallSpecGuardrailIds.verify_persisted(source, winning, known)
      end
    else
      :ok
    end
  end

  defp fetch_known_guardrail_ids(_repository, _tenant_key, _call_spec_id, 1), do: {:ok, %{}}

  defp fetch_known_guardrail_ids(repository, tenant_key, call_spec_id, next) do
    with {:ok, stored} <-
           Repositories.call(repository, :fetch_revision, [tenant_key, call_spec_id, next - 1]) do
      {:ok, CallSpecGuardrailIds.known_ids(stored.source)}
    end
  end

  defp attempt_save(_repository, _tenant_key, _id, _revision, _source, _known, _options, 0),
    do: {:error, :revision_generation_exhausted}

  defp attempt_save(
         repository,
         tenant_key,
         call_spec_id,
         revision_number,
         source,
         known,
         options,
         attempts_left
       ) do
    with {:ok, call_spec} <-
           CallSpec.new(source, resource_id: call_spec_id, revision: revision_number),
         :ok <- preserve_direction(repository, tenant_key, call_spec),
         :ok <- CallSpecCredentials.check(call_spec, tenant_key, options),
         {:ok, protocol} <-
           Vxpipe.CallEngine.AgentProtocol.capture(
             Keyword.get(options, :agent_protocol_version, :mode_message_v1)
           ),
         {:ok, validation_errors, validation_warnings} <-
           validate_draft(
             call_spec,
             tenant_key,
             Keyword.put(options, :agent_protocol, protocol)
           ) do
      routes = participant_routes(call_spec, tenant_key, options)
      telephony_routes = telephony_routes(call_spec, tenant_key)

      revision = %CallSpecRevision{
        tenant_key: tenant_key,
        call_spec_id: call_spec_id,
        revision: revision_number,
        schema_version: call_spec.schema_version,
        source: source,
        source_digest: source_digest(source),
        compiled_metadata: Map.put(compiled_metadata(call_spec), "agent_protocol", protocol),
        validation_errors: validation_errors,
        validation_warnings: validation_warnings,
        routes: routes,
        telephony_routes: telephony_routes,
        published_at: nil,
        inserted_at: now(options)
      }

      result =
        CallSpecCredentials.with_active(call_spec, tenant_key, options, fn ->
          Repositories.call(repository, :insert_revision, [tenant_key, revision, routes])
        end)

      case result do
        {:error, :revision_conflict} ->
          with {:ok, next} <-
                 Repositories.call(repository, :next_revision, [tenant_key, call_spec_id]),
               :ok <-
                 verify_retry_guardrails(
                   repository,
                   tenant_key,
                   call_spec_id,
                   next,
                   source,
                   known
                 ) do
            attempt_save(
              repository,
              tenant_key,
              call_spec_id,
              next,
              source,
              known,
              options,
              attempts_left - 1
            )
          end

        result ->
          result
      end
    end
  end

  defp preserve_direction(_repository, _tenant_key, %CallSpec{revision: 1}), do: :ok

  defp preserve_direction(repository, tenant_key, call_spec) do
    with {:ok, first} <-
           Repositories.call(repository, :fetch_revision, [tenant_key, call_spec.resource_id, 1]) do
      original = if is_map(first.source["outgoing_call"]), do: :outgoing, else: :incoming

      if call_spec.direction == original do
        :ok
      else
        {:error,
         Error.new(:invalid_call_spec, "Call direction cannot be changed.",
           details: %{
             "path" => ["#{call_spec.direction}_call"],
             "reason" => "cannot be changed after creation; create a new call spec"
           }
         )}
      end
    end
  end

  defp validate_draft(call_spec, tenant_key, options) do
    {spec_for_validation, errors} =
      case OpeningAudio.validate_defaults(call_spec.opening_audio, call_spec.default_capabilities) do
        :ok ->
          {call_spec, []}

        {:error, %Error{} = error} ->
          # Check every other runtime setting while preserving the author's opening in the draft.
          {%{call_spec | opening_audio: nil}, [Error.to_public(error)]}
      end

    with :ok <- validate_support(spec_for_validation, tenant_key, options),
         do: {:ok, errors, recording_warnings(call_spec, options)}
  end

  defp validate_support(call_spec, tenant_key, options) do
    invocation_input = %{
      call_spec: %{id: call_spec.resource_id, revision: call_spec.revision},
      initial_variables: %{},
      transport: %{type: "web"}
    }

    with {:ok, invocation} <-
           CallInvocation.new(invocation_input,
             tenant_id: tenant_key,
             actor_id: "call_spec-validation",
             call_id: "call_spec-validation-call",
             room_id: "call_spec-validation-room"
           ),
         {:ok, _plan} <- CallPlanCompiler.compile(call_spec, invocation, options) do
      :ok
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, _reason} -> {:error, :call_spec_validation_unavailable}
    end
  end

  # D4: a revision that requests recording on an installation without
  # recording storage warns instead of failing. Warnings never block
  # publication; the call proceeds unrecorded.
  defp recording_warnings(call_spec, options) do
    if call_spec.media_policy.record_audio == true and not recording_available?(options) do
      [
        %{
          "code" => "recording_unavailable",
          "path" => ["media_policy", "record_audio"],
          "reason" =>
            "Recording was requested but this installation has no recording storage. The call will proceed without being recorded."
        }
      ]
    else
      []
    end
  end

  defp recording_available?(options) do
    case Keyword.fetch(options, :recording_available) do
      {:ok, available?} -> available?
      :error -> Application.get_env(:vxpipe_calls, :recording_available, true)
    end
  end

  defp with_current_warnings(%CallSpecRevision{} = stored, options) do
    case CallSpec.new(stored.source,
           resource_id: stored.call_spec_id,
           revision: stored.revision
         ) do
      {:ok, call_spec} ->
        %{stored | validation_warnings: recording_warnings(call_spec, options)}

      {:error, _reason} ->
        stored
    end
  end

  defp participant_routes(call_spec, tenant_key, options) do
    call_spec.participants
    |> Enum.filter(fn {_ref, participant} ->
      participant.connection && participant.connection.service == :web
    end)
    |> Enum.map(fn {participant_ref, _participant} ->
      %ParticipantRoute{
        key: uuid(options),
        tenant_key: tenant_key,
        call_spec_id: call_spec.resource_id,
        call_spec_revision: call_spec.revision,
        participant_ref: participant_ref,
        published_at: nil
      }
    end)
    |> Enum.sort_by(& &1.participant_ref)
  end

  defp telephony_routes(call_spec, tenant_key) do
    call_spec.participants
    |> Enum.filter(fn {_ref, participant} -> inbound_telephony?(participant.connection) end)
    |> Enum.map(fn {participant_ref, participant} ->
      connection = participant.connection

      %TelephonyRoute{
        tenant_key: tenant_key,
        call_spec_id: call_spec.resource_id,
        call_spec_revision: call_spec.revision,
        participant_ref: participant_ref,
        service: connection.service,
        number: connection.number,
        published_at: nil
      }
    end)
    |> Enum.sort_by(& &1.participant_ref)
  end

  defp inbound_telephony?(%{
         service: service,
         mode: :receive,
         admission: :start_call,
         number: number
       })
       when is_binary(service) and is_binary(number),
       do: true

  defp inbound_telephony?(_connection), do: false

  defp telephony_scope({:tenant, tenant_key}) when is_binary(tenant_key), do: :ok
  defp telephony_scope(_invalid), do: {:error, :invalid_telephony_route}

  defp compiled_metadata(call_spec) do
    participants =
      Map.new(call_spec.participants, fn {ref, participant} ->
        connection =
          if participant.connection do
            connection_metadata(participant.connection)
          end

        {ref,
         %{
           "kind" => Atom.to_string(participant.kind),
           "connection" => connection
         }}
      end)

    %{
      "entry_caller" => call_spec.entry_caller,
      "entry_receiver" => call_spec.entry_receiver,
      "direction" => Atom.to_string(call_spec.direction),
      "ring_timeout_ms" => call_spec.ring_timeout_ms,
      "participants" => participants,
      "schema_version" => call_spec.schema_version
    }
  end

  defp connection_metadata(connection) do
    %{
      "admission" => Atom.to_string(connection.admission),
      "mode" => Atom.to_string(connection.mode),
      "service" => connection_service(connection.service)
    }
    |> maybe_put("number", connection.number)
    |> maybe_put("number_from_variable", number_source(connection.number_from_variable))
  end

  defp connection_service(:web), do: "web"
  defp connection_service(service) when is_binary(service), do: service

  defp number_source(nil), do: nil

  defp number_source(source) do
    %{"section" => source.section, "variable" => source.variable}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp source_digest(source) do
    source
    |> JSON.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp public_source(source) do
    case PrivateMaterial.path(source) do
      nil ->
        :ok

      path ->
        {:error,
         Error.new(:private_call_spec_material, "The call spec contains private material.",
           details: %{"path" => path, "reason" => "must not contain credentials or secrets"}
         )}
    end
  end

  defp json_safe(source) do
    try do
      source
      |> JSON.encode!()
      |> JSON.decode()
    rescue
      _error -> {:error, :invalid_call_spec_source}
    end
  end

  defp publishable(%CallSpecRevision{validation_errors: []}), do: :ok

  defp publishable(%CallSpecRevision{validation_errors: errors}),
    do: {:error, {:call_spec_not_publishable, errors}}

  defp now(options), do: Keyword.get_lazy(options, :now, &DateTime.utc_now/0)

  defp uuid(options) do
    options
    |> Keyword.get(:uuid_generator, &PublicId.uuid/0)
    |> then(& &1.())
  end
end
