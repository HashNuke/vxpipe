defmodule Vxpipe.CallEngine.Tool.ParticipantTransfer do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomRegistry
  alias Vxpipe.CallEngine.Guardrails.{Deadline, TransferAdmission}
  alias Vxpipe.CallEngine.Tool.Definition
  alias Vxpipe.CallEngine.Tool.{Context, PlatformResult}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.{Binding, Request}

  # Bound for one execution-time transfer check (native path and unadmitted
  # fallback). Joint admission carries its own response intersected deadline.

  @spec definition(Binding.t()) :: Definition.t()
  def definition(%Binding{} = binding) do
    targets =
      binding.targets
      |> Enum.sort_by(fn {call_spec_key, _target} -> call_spec_key end)

    %Definition{
      name: "transfer",
      description: "Transfer the caller to one permitted participant.",
      parameters: parameters(targets)
    }
  end

  defp parameters(targets) do
    required_reason_targets =
      Enum.filter(targets, fn {_call_spec_key, target} -> target.reason_required end)

    parameters = %{
      "type" => "object",
      "properties" => %{
        "destination" => destination_schema(targets)
      },
      "required" => ["destination"],
      "additionalProperties" => false
    }

    add_reason(
      parameters,
      required_reason_targets,
      length(required_reason_targets) == length(targets)
    )
  end

  defp add_reason(parameters, [], _required_for_every_target?), do: parameters

  defp add_reason(parameters, required_targets, required_for_every_target?) do
    destination_keys =
      Enum.map(required_targets, fn {call_spec_key, _target} -> call_spec_key end)

    reason = %{
      "type" => "string",
      "minLength" => 1,
      "maxLength" => 1_024,
      "description" =>
        "Required for #{destination_label(destination_keys)}. Explain why the caller is being transferred."
    }

    parameters = put_in(parameters, ["properties", "reason"], reason)

    if required_for_every_target? do
      Map.put(parameters, "required", ["destination", "reason"])
    else
      parameters
    end
  end

  defp destination_label([call_spec_key]), do: "destination #{call_spec_key}"
  defp destination_label(call_spec_keys), do: "destinations #{Enum.join(call_spec_keys, ", ")}"

  defp destination_schema(targets) do
    label = if match?([_target], targets), do: "destination", else: "destinations"

    %{
      "type" => "string",
      "enum" => Enum.map(targets, fn {call_spec_key, _target} -> call_spec_key end),
      "description" =>
        "Permitted #{label}: " <> Enum.map_join(targets, ", ", &describe_target/1) <> "."
    }
  end

  defp describe_target({call_spec_key, %{description: description}})
       when is_binary(description),
       do: "#{call_spec_key} (#{description})"

  defp describe_target({call_spec_key, _target}), do: call_spec_key

  @spec execute(Binding.t(), map(), Context.t()) ::
          {:ok, PlatformResult.t()}
          | {:error,
             :tool_failed
             | :rejected
             | :transfer_denied
             | :transfer_unavailable
             | {:transfer_denied, Vxpipe.CallEngine.Tool.InvocationCompletion.denial()}}
  def execute(%Binding{} = binding, arguments, %Context{} = context) when is_map(arguments) do
    with {:ok, request} <- Request.new(binding, arguments, context),
         deadline = transfer_deadline(binding, context),
         :ok <- admit_deadline(deadline),
         {:ok, request} <- admit_execution(binding, request, deadline),
         :ok <- admit_deadline(deadline) do
      case Vxpipe.CallEngine.RoomAuthority.transfer(request) do
        {:ok, result} ->
          {:ok, %PlatformResult{effect: :participant_transfer_committed, result: result}}

        {:error, :rejected} ->
          {:error, :rejected}

        {:error, _unavailable} ->
          {:error, :tool_failed}
      end
    else
      {:error, reason} when reason in [:rejected, :transfer_denied, :transfer_unavailable] ->
        {:error, reason}

      {:error, {:transfer_denied, _}} = denied ->
        denied

      _rejected_or_unavailable ->
        {:error, :tool_failed}
    end
  end

  defp transfer_deadline(%Binding{guardrails_policy_digest: nil}, _context), do: nil

  defp transfer_deadline(_binding, context),
    do: Deadline.intersect(Deadline.response(context), context.deadline_ms)

  defp admit_deadline(nil), do: :ok

  defp admit_deadline(deadline),
    do: if(Deadline.open?(deadline), do: :ok, else: {:error, :transfer_unavailable})

  # Invocation-bound Before-outgoing-transfer admission at effect time.
  # Reuses joint admission or binds a fresh worker check. The room consumes
  # the bound entry when it authorizes this particular transfer.
  @spec admit_execution(Binding.t(), Request.t(), integer() | nil) ::
          {:ok, Request.t()}
          | {:error,
             :transfer_denied
             | :transfer_unavailable
             | {:transfer_denied, Vxpipe.CallEngine.Tool.InvocationCompletion.denial()}}
  defp admit_execution(%Binding{guardrails_policy_digest: nil}, %Request{} = request, _),
    do: {:ok, request}

  defp admit_execution(%Binding{} = binding, %Request{} = request, deadline) do
    case Vxpipe.CallEngine.RoomAuthority.take_transfer_verdict(
           request.tenant_id,
           request.room_id,
           {request.command_id, request.tool_call_id}
         ) do
      {:ok, _entry} ->
        {:ok, request}

      :empty when request.request_origin in [:caller, :engine] ->
        {:error, :transfer_unavailable}

      :empty ->
        fresh_transfer_check(binding, request, deadline)

      {:error, _unavailable} ->
        {:error, :transfer_unavailable}
    end
  end

  defp fresh_transfer_check(%Binding{} = binding, %Request{} = request, deadline) do
    attrs = %{
      guardrails: guardrails_server(binding.source_activation_id),
      policy_digest: binding.guardrails_policy_digest,
      activation_id: binding.source_activation_id,
      invocation_id: request.tool_call_id,
      incarnation_id: request.incarnation_id,
      destination: request.destination_call_spec_key,
      reason: request.reason,
      text: nil,
      check: nil,
      response_deadline_ms: deadline
    }

    case TransferAdmission.check_transfer(attrs) do
      :passed ->
        entry = %{
          verdict: :passed,
          source: :checked,
          policy_digest: binding.guardrails_policy_digest,
          policy_revision: binding.guardrails_policy_revision,
          checked_at_ms: System.monotonic_time(:millisecond),
          incarnation_id: request.incarnation_id,
          invocation_id: request.tool_call_id,
          command_id: request.command_id,
          expires_at_ms: deadline,
          source_participant_id: request.source_participant_id,
          source_activation_id: request.source_activation_id,
          destination_call_spec_key: request.destination_call_spec_key
        }

        case Vxpipe.CallEngine.RoomAuthority.bind_transfer_verdict(
               request.tenant_id,
               request.room_id,
               entry
             ) do
          :ok -> {:ok, request}
          {:error, _} -> {:error, :transfer_unavailable}
        end

      {:blocked, lines, callback} ->
        note_transfer_denial(request)
        {:error, {:transfer_denied, %{messages: lines, on_dispatch: callback}}}

      {:blocked, lines} ->
        note_transfer_denial(request)
        {:error, {:transfer_denied, lines}}

      {:error, _reason} ->
        {:error, :transfer_unavailable}
    end
  end

  defp guardrails_server(activation_id) when is_binary(activation_id) do
    GenServer.whereis(
      {:via, Registry, {RoomRegistry, {:agent_activation, activation_id, :guardrails}}}
    )
  end

  defp guardrails_server(_activation_id), do: nil

  defp note_transfer_denial(%Request{} = request) do
    Vxpipe.CallEngine.RoomAuthority.note_transfer_denial(
      request.tenant_id,
      request.room_id,
      %{request | reason: nil, announcement: nil}
    )
  end
end
